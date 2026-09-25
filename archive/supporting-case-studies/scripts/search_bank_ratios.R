library(DBI)
library(duckdb)
library(yaml)

cfg <- yaml::read_yaml("config.yml")$default
con <- dbConnect(duckdb(shared_home = FALSE),
  dbdir = file.path(cfg$upstream_root, "database/research.duckdb"), read_only = TRUE
)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

sql <- paste(
  "SELECT label_text, right(item, 4) AS item_suffix, COUNT(*) AS n_records,",
  "MIN(normalized_value) AS min_value, MAX(normalized_value) AS max_value",
  "FROM bank_risk__bank_quarterly_panel",
  "WHERE lower(label_text) LIKE '%ratio%' OR lower(label_text) LIKE '%return on%'",
  "OR lower(label_text) LIKE '%risk exposure amount%'",
  "GROUP BY label_text, right(item, 4)",
  "ORDER BY n_records DESC LIMIT 150"
)
print(dbGetQuery(con, sql), row.names = FALSE)

