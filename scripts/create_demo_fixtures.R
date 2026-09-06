library(DBI)
library(duckdb)

dir.create("data/demo/input", recursive = TRUE, showWarnings = FALSE)
con <- dbConnect(duckdb(shared_home = FALSE), dbdir = ":memory:")
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

copy_csv <- function(query, path) {
  normalized <- normalizePath(path, winslash = "/", mustWork = FALSE)
  dbExecute(con, sprintf("COPY (%s) TO '%s' (HEADER, DELIMITER ',')", query, normalized))
}

copy_csv("
  SELECT date, log_return, rv_1d, log_har_daily, log_har_weekly,
    log_har_monthly, log_vix, log_forward_rv_5d, target_available_date_5d
  FROM read_parquet('data/gold/macro_vol/forecast_panel.parquet')
  WHERE log_forward_rv_5d IS NOT NULL AND log_vix IS NOT NULL
  ORDER BY date DESC LIMIT 1400
", "data/demo/input/macro_fixture.csv")

copy_csv("
  SELECT bank_id, bank_name, country, quarter, CET1_model, leverage_ratio_model,
    RWA_density, ROA, overall_risk_score, availability_date_method, point_in_time_status
  FROM read_parquet('data/gold/bank_risk/bank_risk_features.parquet')
  WHERE bank_id IN (
    SELECT bank_id FROM read_parquet('data/gold/bank_risk/bank_risk_features.parquet')
    GROUP BY bank_id ORDER BY bank_id LIMIT 24
  ) ORDER BY bank_id, quarter
", "data/demo/input/bank_fixture.csv")

copy_csv("
  SELECT * FROM read_parquet('data/gold/fundamentals/company_kpis.parquet')
  WHERE CIK IN (
    SELECT CIK FROM read_parquet('data/gold/fundamentals/company_kpis.parquet')
    GROUP BY CIK ORDER BY CIK LIMIT 30
  ) ORDER BY CIK, frequency, fiscal_year, fiscal_period, kpi
", "data/demo/input/fundamentals_fixture.csv")

cat("Demo fixtures written to data/demo/input\n")
