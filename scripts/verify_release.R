library(DBI)
library(duckdb)
library(data.table)
library(jsonlite)

fail <- function(message) stop(message, call. = FALSE)

con <- dbConnect(duckdb(shared_home = FALSE), dbdir = ":memory:")
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
source_metrics <- as.data.table(dbGetQuery(con,
  "SELECT * FROM read_parquet('data/gold/macro_vol/model_metrics.parquet')"))
public_metrics <- fread("results/model_metrics.csv")
source_predictions <- as.data.table(dbGetQuery(con,
  "SELECT * FROM read_parquet('data/gold/macro_vol/walk_forward_predictions.parquet')"))
setorder(source_metrics, horizon, rank_QLIKE, model)
setorder(public_metrics, horizon, rank_QLIKE, model)
if (!isTRUE(all.equal(source_metrics, public_metrics,
  check.attributes = FALSE, tolerance = 1e-12))) {
  fail("Public model_metrics.csv differs from the saved Parquet result")
}

best <- public_metrics[, .SD[which.min(QLIKE)], by = horizon]
expected_models <- c(
  `1` = "Elastic_Net",
  `5` = "Elastic_Net",
  `10` = "HAR_VIX",
  `22` = "HAR_VIX"
)
expected_qlike <- c(
  `1` = -6.582415579188296,
  `5` = -6.681831587437280,
  `10` = -5.91659285824480,
  `22` = -4.94643130549219
)
if (sum(public_metrics$forecasts) != 127218L) fail("Forecast count is not 127,218")
if (nrow(public_metrics) != 28L) fail("Expected 28 model-horizon rows")
if (!all(best$model == expected_models[as.character(best$horizon)]))
  fail("Lowest-QLIKE models differ from the corrected headline")
if (max(abs(best$QLIKE - expected_qlike[as.character(best$horizon)])) >= 1e-12) {
  fail("Headline QLIKE values differ from the saved result")
}

headline <- read_json("results/headline_metrics.json", simplifyVector = TRUE)
failed_forecasts <- sum(!is.finite(source_predictions$prediction))
if (!identical(headline$method_revision,
      "glmnet_lambda_mapping_corrected_2026-09") ||
    headline$model_forecasts != 127218L ||
    headline$failed_forecast_rows != failed_forecasts ||
    headline$model_horizon_combinations != 28L ||
    headline$unique_forecast_dates != 4552L ||
    headline$first_forecast_date != "2008-07-03" ||
    headline$last_forecast_date != "2026-08-07") {
  fail("headline_metrics.json is inconsistent")
}

required <- c(
  "README.md", "report/analysis.md", "results/model_metrics.csv",
  "results/dm_tests.csv", "results/regime_metrics.csv",
  "results/vintage_coverage.csv", "results/headline_metrics.json",
  "data/demo/input/macro_fixture.csv", "demo/output/macro_demo.html",
  "demo/output/runtime.json", "figures/benchmark-relative-qlike.png"
)
figures <- list.files("figures/macro_gallery", pattern = "\\.png$", full.names = TRUE)
if (length(figures) != 10L) fail("Expected exactly ten public macro gallery figures")
required <- c(required, figures)
missing <- required[!file.exists(required)]
if (length(missing)) fail(paste("Missing release files:", paste(missing, collapse = ", ")))

png_signature <- as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a))
for (path in c("figures/benchmark-relative-qlike.png", figures)) {
  con_file <- file(path, "rb")
  signature <- readBin(con_file, "raw", n = 8L)
  close(con_file)
  if (!identical(signature, png_signature)) fail(paste(path, "is not a valid PNG"))
}

runtime <- read_json("demo/output/runtime.json", simplifyVector = TRUE)
if (!identical(runtime$status, "completed") || !isTRUE(runtime$within_runtime_contract)) {
  fail("The clean deterministic demo did not complete within its runtime contract")
}

cat("Release verification passed:\n")
cat("- saved Parquet and public CSV metrics match\n")
cat("- 127,218 forecasts across 28 combinations\n")
cat("- Elastic Net leads QLIKE at 1d/5d; HAR-VIX leads at 10d/22d\n")
cat("- headline JSON and required files are consistent\n")
cat("- all eleven public PNG files have valid signatures\n")
cat("- clean demo runtime contract passed\n")
