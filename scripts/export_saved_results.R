library(DBI)
library(duckdb)
library(data.table)
library(jsonlite)
library(knitr)

r_files <- list.files("R", pattern = "\\.[Rr]$", recursive = TRUE, full.names = TRUE)
invisible(lapply(r_files, source))

source_dir <- "data/gold/macro_vol"
required <- file.path(source_dir, c(
  "model_metrics.parquet", "dm_tests.parquet", "regime_metrics.parquet",
  "vintage_coverage.parquet", "walk_forward_predictions.parquet"
))
if (!all(file.exists(required))) {
  stop("Saved macro Parquet outputs are missing; run the full targets pipeline first")
}

con <- dbConnect(duckdb(shared_home = FALSE), dbdir = ":memory:")
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
read_parquet <- function(path) {
  as.data.table(dbGetQuery(con, sprintf("SELECT * FROM read_parquet(%s)", sql_path(path))))
}

evaluation <- list(
  metrics = read_parquet(required[[1L]]),
  dm_tests = read_parquet(required[[2L]]),
  regime_metrics = read_parquet(required[[3L]])
)
coverage <- read_parquet(required[[4L]])
predictions <- read_parquet(required[[5L]])
config <- list(project_root = normalizePath(".", winslash = "/", mustWork = TRUE))

paths <- write_public_macro_results(evaluation, coverage, predictions, config)
report <- write_macro_report(evaluation, coverage, predictions, config)


cat("Exported", length(paths), "result files and", report, "\n")
