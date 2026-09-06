library(DBI)
library(duckdb)

con <- dbConnect(duckdb(shared_home = FALSE), dbdir = ":memory:")
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

best_bank <- dbGetQuery(con, "
  SELECT horizon, model, ROUND(RMSE, 6) AS RMSE, ROUND(R2_OOS, 4) AS R2_OOS
  FROM read_parquet('data/gold/bank_risk/model_metrics.parquet')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY horizon ORDER BY RMSE) = 1
  ORDER BY horizon
")
best_macro <- dbGetQuery(con, "
  SELECT horizon, model, ROUND(QLIKE, 6) AS QLIKE, ROUND(RMSE, 6) AS RMSE
  FROM read_parquet('data/gold/macro_vol/model_metrics.parquet')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY horizon ORDER BY QLIKE) = 1
  ORDER BY horizon
")
quality <- dbGetQuery(con, "
  SELECT
    SUM(identity_flag::INTEGER) AS identity_flags,
    SUM(future_period_flag::INTEGER) AS future_period_flags,
    SUM(period_after_filing_flag::INTEGER) AS period_after_filing_flags,
    SUM(duplicate_vintage_flag::INTEGER) AS duplicate_vintage_flags
  FROM read_parquet('data/gold/fundamentals/accounting_quality_flags.parquet')
")

cat("BANK\n")
write.table(best_bank, row.names = FALSE, sep = "|")
cat("MACRO\n")
write.table(best_macro, row.names = FALSE, sep = "|")
cat("QUALITY\n")
write.table(quality, row.names = FALSE, sep = "|")

catalog_con <- dbConnect(duckdb(shared_home = FALSE),
  dbdir = "database/research.duckdb", read_only = TRUE)
on.exit(dbDisconnect(catalog_con, shutdown = TRUE), add = TRUE)
cat("DATABASE_OBJECTS\n")
cat(length(dbListTables(catalog_con)), "registered tables/views\n")
