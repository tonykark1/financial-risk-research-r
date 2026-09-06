library(DBI)
library(duckdb)
library(yaml)

cfg <- yaml::read_yaml("config.yml")$default
con <- dbConnect(duckdb(shared_home = FALSE),
  dbdir = file.path(cfg$upstream_root, "database/research.duckdb"), read_only = TRUE
)
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

terms <- c(
  "cet1", "tier 1", "capital ratio", "leverage ratio", "risk exposure amount",
  "total assets", "non-performing", "npl", "coverage ratio", "return on assets",
  "return on equity", "net interest margin", "cost-to-income", "cost income"
)
for (term in terms) {
  cat("\nTERM:", term, "\n")
  sql <- paste0(
    "SELECT item, label_text, domain, exercise, COUNT(*) AS n_records, ",
    "MIN(normalized_value) AS min_value, MAX(normalized_value) AS max_value ",
    "FROM bank_risk__bank_quarterly_panel ",
    "WHERE lower(label_text) LIKE ? ",
    "GROUP BY item, label_text, domain, exercise ",
    "ORDER BY n_records DESC LIMIT 20"
  )
  print(dbGetQuery(con, sql, params = list(paste0("%", term, "%"))), row.names = FALSE)
}

