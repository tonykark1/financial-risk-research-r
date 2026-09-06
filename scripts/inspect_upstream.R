library(DBI)
library(duckdb)

source("R/utils.R")
cfg <- project_config()
upstream_db <- file.path(cfg$upstream_root, cfg$upstream_duckdb)

con <- dbConnect(duckdb(shared_home = FALSE), dbdir = upstream_db, read_only = TRUE)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

queries <- list(
  bank_overview = paste(
    "SELECT COUNT(*) n_rows, COUNT(DISTINCT LEI) leis,",
    "COUNT(DISTINCT observation_period) periods,",
    "MIN(observation_period) start_period, MAX(observation_period) end_period,",
    "COUNT(DISTINCT item) items",
    "FROM bank_risk__bank_quarterly_panel"
  ),
  bank_items = paste(
    "SELECT item, any_value(label_text) AS label_text_sample,",
    "COUNT(*) AS n_records, COUNT(normalized_value) AS n_value",
    "FROM bank_risk__bank_quarterly_panel",
    "GROUP BY item ORDER BY n_value DESC LIMIT 80"
  ),
  macro = paste(
    "SELECT series_id, any_value(variable) AS variable_name,",
    "MIN(reference_date) AS min_date, MAX(reference_date) AS max_date,",
    "COUNT(*) AS n_records,",
    "SUM(CASE WHEN vintage_available THEN 1 ELSE 0 END) AS n_vintage",
    "FROM macro_forecasting__macro_vintages_long",
    "GROUP BY series_id ORDER BY n_records DESC"
  ),
  market = paste(
    "SELECT instrument_id, MIN(date) AS min_date, MAX(date) AS max_date,",
    "COUNT(*) AS n_records",
    "FROM macro_forecasting__market_daily GROUP BY instrument_id",
    "ORDER BY instrument_id"
  ),
  realized_volatility = paste(
    "SELECT instrument_id, MIN(date) AS min_date, MAX(date) AS max_date,",
    "COUNT(*) AS n_records",
    "FROM macro_forecasting__realized_volatility GROUP BY instrument_id",
    "ORDER BY instrument_id"
  ),
  fundamentals = paste(
    "SELECT COUNT(*) n_rows, COUNT(DISTINCT CIK) companies,",
    "MIN(period_end) min_period, MAX(period_end) max_period,",
    "MIN(available_at) min_available, MAX(available_at) max_available",
    "FROM fundamentals__company_fundamentals_wide"
  ),
  filings = paste(
    "SELECT COUNT(*) n_rows, COUNT(DISTINCT CIK) companies,",
    "MIN(filing_date) min_filed, MAX(filing_date) max_filed,",
    "SUM(CASE WHEN amendment_flag = '1' THEN 1 ELSE 0 END) amendments",
    "FROM fundamentals__filing_metadata"
  )
)

for (query_name in names(queries)) {
  cat("\n", toupper(query_name), "\n", sep = "")
  print(dbGetQuery(con, queries[[query_name]]), row.names = FALSE)
}

