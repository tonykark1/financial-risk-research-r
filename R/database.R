sql_path <- function(path) {
  paste0("'", gsub("'", "''", normalizePath(path, winslash = "/", mustWork = FALSE),
    fixed = TRUE), "'")
}

connect_research_db <- function(config, read_only = FALSE) {
  path <- project_path(config$database_path, root = config$project_root)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = path, read_only = read_only)
}

disconnect_research_db <- function(con) {
  DBI::dbDisconnect(con, shutdown = TRUE)
  invisible(TRUE)
}

upstream_gold_views <- function(config) {
  catalog <- data.table::fread(upstream_path(config, config$upstream_catalog), na.strings = c("", "NA"))
  catalog <- catalog[!is.na(gold_path) & nzchar(gold_path)]
  catalog[, view_name := paste0(
    "upstream__",
    gsub("[^a-z0-9]+", "_", tolower(dataset))
  )]
  catalog[, absolute_path := upstream_path(config, gold_path)]
  catalog[]
}

register_upstream_views <- function(config) {
  con <- connect_research_db(config)
  on.exit(disconnect_research_db(con), add = TRUE)
  views <- upstream_gold_views(config)
  for (i in seq_len(nrow(views))) {
    path <- views$absolute_path[[i]]
    if (dir.exists(path)) path <- file.path(path, "*.parquet")
    statement <- sprintf(
      "CREATE OR REPLACE VIEW %s AS SELECT * FROM read_parquet(%s, union_by_name = true)",
      DBI::dbQuoteIdentifier(con, views$view_name[[i]]), sql_path(path)
    )
    DBI::dbExecute(con, statement)
  }
  views[, .(dataset, view_name, absolute_path)]
}

upstream_connection <- function(config) {
  path <- upstream_path(config, config$upstream_duckdb)
  DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = path, read_only = TRUE)
}

table_schema <- function(con, table) {
  data.table::as.data.table(DBI::dbGetQuery(
    con, paste("DESCRIBE", DBI::dbQuoteIdentifier(con, table))
  ))
}

