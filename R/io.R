upstream_path <- function(config, ...) {
  normalizePath(file.path(config$upstream_root, ...), winslash = "/", mustWork = FALSE)
}

repository_file_inventory <- function(config) {
  root <- config$upstream_root
  files <- suppressWarnings(list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE,
    include.dirs = FALSE, no.. = TRUE
  ))
  files <- files[!grepl("/(\\.vendor|\\.pytest_cache)/", normalizePath(files,
    winslash = "/", mustWork = FALSE
  ))]
  info <- file.info(files)
  rel <- substring(normalizePath(files, winslash = "/", mustWork = FALSE), nchar(root) + 2L)
  ext <- tolower(tools::file_ext(files))
  data.table::data.table(
    source = "supplied_local_lake",
    dataset_name = basename(files),
    file_path = rel,
    absolute_path = normalizePath(files, winslash = "/", mustWork = FALSE),
    format = ifelse(nzchar(ext), ext, "none"),
    size_bytes = as.numeric(info$size),
    last_updated = as.POSIXct(info$mtime, tz = "UTC"),
    notes = NA_character_
  )
}

write_parquet_duckdb <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbWriteTable(con, "write_buffer", as.data.frame(x), overwrite = TRUE)
  quoted <- gsub("'", "''", normalizePath(path, winslash = "/", mustWork = FALSE), fixed = TRUE)
  DBI::dbExecute(con, sprintf(
    "COPY write_buffer TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)", quoted
  ))
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

read_parquet_sql <- function(path, sql = "SELECT * FROM source") {
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  quoted <- gsub("'", "''", normalizePath(path, winslash = "/", mustWork = TRUE), fixed = TRUE)
  DBI::dbExecute(con, sprintf(
    "CREATE VIEW source AS SELECT * FROM read_parquet('%s', union_by_name = true)", quoted
  ))
  data.table::as.data.table(DBI::dbGetQuery(con, sql))
}

copy_query_to_parquet <- function(con, query, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  quoted <- gsub("'", "''", normalizePath(path, winslash = "/", mustWork = FALSE), fixed = TRUE)
  DBI::dbExecute(con, sprintf(
    "COPY (%s) TO '%s' (FORMAT PARQUET, COMPRESSION ZSTD)", query, quoted
  ))
  normalizePath(path, winslash = "/", mustWork = TRUE)
}
