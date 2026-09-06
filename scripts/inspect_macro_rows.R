library(DBI)
library(duckdb)
library(yaml)

cfg <- yaml::read_yaml("config.yml")$default
con <- dbConnect(duckdb(shared_home = FALSE),
  dbdir = file.path(cfg$upstream_root, "database/research.duckdb"), read_only = TRUE
)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
sql <- paste(
  "SELECT series_id, observation_period, reference_date, date, available_at,",
  "vintage_start, vintage_end, normalized_value, value, vintage_available",
  "FROM macro_forecasting__macro_vintages_long",
  "WHERE series_id IN ('DFF','DGS10','VIXCLS','GDPC1') AND vintage_available = true",
  "ORDER BY series_id, coalesce(date, observation_period), available_at LIMIT 40"
)
print(dbGetQuery(con, sql), row.names = FALSE)
