library(DBI)
library(duckdb)

con <- dbConnect(duckdb(shared_home = FALSE), dbdir = ":memory:")
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

facts <- "data/gold/fundamentals/company_fundamentals_duration_normalized.parquet"
kpis <- "data/gold/fundamentals/company_kpis.parquet"

cat("FACT PERIOD CLASSES\n")
write.table(dbGetQuery(con, sprintf("
  SELECT fact_period_type, comparison_eligible, COUNT(*) AS facts
  FROM read_parquet('%s') GROUP BY 1,2 ORDER BY 1,2", facts)),
  row.names = FALSE, sep = "|")

cat("KPI FREQUENCIES\n")
write.table(dbGetQuery(con, sprintf("
  SELECT frequency, COUNT(*) AS records, COUNT(DISTINCT CIK) AS companies,
    COUNT(DISTINCT kpi) AS kpis,
    COUNT(DISTINCT CIK || '|' || fiscal_year || '|' || fiscal_period) AS company_periods,
    COUNT(DISTINCT normalization_method) AS normalization_methods
  FROM read_parquet('%s') GROUP BY 1 ORDER BY 1", kpis)),
  row.names = FALSE, sep = "|")

cat("KPI TOTAL\n")
write.table(dbGetQuery(con, sprintf("
  SELECT COUNT(*) AS records, COUNT(DISTINCT CIK) AS companies,
    COUNT(DISTINCT kpi) AS kpis
  FROM read_parquet('%s')", kpis)), row.names = FALSE, sep = "|")

cat("CONTRACT VIOLATIONS\n")
write.table(dbGetQuery(con, sprintf("
  SELECT
    SUM(CAST(frequency NOT IN ('quarterly','annual') AS INTEGER)) AS invalid_frequency,
    SUM(CAST(normalization_method <> 'direct_reported_duration_first_vintage' AS INTEGER)) AS invalid_method,
    SUM(CAST(TRY_CAST(period_end AS DATE) > TRY_CAST(available_at AS DATE) AS INTEGER)) AS future_periods,
    COUNT(*) - COUNT(DISTINCT CIK || '|' || frequency || '|' || fiscal_year || '|' || fiscal_period || '|' || kpi) AS duplicate_or_null_kpi_keys
  FROM read_parquet('%s')", kpis)), row.names = FALSE, sep = "|")
