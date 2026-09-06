library(DBI)
library(duckdb)
library(yaml)

cfg <- yaml::read_yaml("config.yml")$default
con <- dbConnect(duckdb(shared_home = FALSE), dbdir = ":memory:")
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
paths <- c(
  "catalog/entity_master.parquet",
  "catalog/identifier_crosswalk.parquet",
  "catalog/bank_identifier_crosswalk.parquet",
  "catalog/bank_security_crosswalk.parquet",
  "catalog/eba_bank_master.parquet"
)
for (relative_path in paths) {
  cat("\n", relative_path, "\n", sep = "")
  path <- normalizePath(file.path(cfg$upstream_root, relative_path), winslash = "/")
  path <- gsub("'", "''", path, fixed = TRUE)
  schema <- dbGetQuery(con, sprintf(
    "DESCRIBE SELECT * FROM read_parquet('%s')", path
  ))
  print(schema[, 1:2], row.names = FALSE)
  print(dbGetQuery(con, sprintf(
    "SELECT * FROM read_parquet('%s') LIMIT 2", path
  )), row.names = FALSE)
}

