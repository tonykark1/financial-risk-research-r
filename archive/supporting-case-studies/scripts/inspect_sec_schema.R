library(DBI)
library(duckdb)

source("R/utils.R")
cfg <- project_config()
root <- file.path(cfg$upstream_root, "data/gold/fundamentals")
con <- dbConnect(duckdb(shared_home = FALSE), dbdir = ":memory:")
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

for (file in c("company_fundamentals_selected.parquet",
               "company_fundamentals_wide.parquet",
               "filing_metadata.parquet")) {
  cat("\nFILE ", file, "\n", sep = "")
  query <- sprintf("DESCRIBE SELECT * FROM read_parquet('%s/%s')", root, file)
  schema <- dbGetQuery(con, query)
  write.table(schema[, 1:2], row.names = FALSE, sep = "|")
}

cat("\nSELECTED FORMS / PERIOD FIELDS\n")
selected <- sprintf("%s/company_fundamentals_selected.parquet", root)
print(dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s') LIMIT 3", selected)))

cat("\nDURATION PROFILE\n")
profile <- dbGetQuery(con, sprintf("
  SELECT standardized_concept, form,
    CASE
      WHEN start_date IS NULL OR TRY_CAST(start_date AS DATE) IS NULL THEN 'instant'
      WHEN date_diff('day', TRY_CAST(start_date AS DATE), TRY_CAST(end_date AS DATE)) BETWEEN 70 AND 110 THEN 'quarterly'
      WHEN date_diff('day', TRY_CAST(start_date AS DATE), TRY_CAST(end_date AS DATE)) BETWEEN 330 AND 380 THEN 'annual'
      WHEN date_diff('day', TRY_CAST(start_date AS DATE), TRY_CAST(end_date AS DATE)) BETWEEN 120 AND 329 THEN 'ytd_or_other'
      ELSE 'other'
    END AS period_class,
    COUNT(*) AS facts
  FROM read_parquet('%s')
  GROUP BY 1,2,3 ORDER BY 1,2,3
", selected))
write.table(profile, row.names = FALSE, sep = "|")


