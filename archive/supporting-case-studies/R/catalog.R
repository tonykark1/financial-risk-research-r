detect_dimension <- function(columns) {
  candidates <- c("LEI", "CIK", "instrument_id", "entity_id", "bank_id")
  paste(intersect(candidates, columns), collapse = ",")
}

detect_country_dimension <- function(columns) {
  candidates <- c("country", "geography", "legal_address_country")
  paste(intersect(candidates, columns), collapse = ",")
}

first_nonmissing_value <- function(con, table, column) {
  sql <- sprintf(
    "SELECT CAST(%s AS VARCHAR) AS value FROM %s WHERE %s IS NOT NULL LIMIT 1",
    DBI::dbQuoteIdentifier(con, column), DBI::dbQuoteIdentifier(con, table),
    DBI::dbQuoteIdentifier(con, column)
  )
  value <- DBI::dbGetQuery(con, sql)$value
  if (length(value)) value[[1L]] else NA_character_
}

build_data_catalog <- function(config, output = "data/gold/data_catalog.parquet") {
  source_catalog <- data.table::fread(
    upstream_path(config, config$upstream_catalog), na.strings = c("", "NA")
  )
  con <- upstream_connection(config)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  tables <- DBI::dbGetQuery(con, "SHOW TABLES")$name
  rows <- lapply(seq_len(nrow(source_catalog)), function(i) {
    record <- source_catalog[i]
    table <- tables[endsWith(tables, paste0("__", record$dataset))][1L]
    if (is.na(table)) return(NULL)
    schema <- table_schema(con, table)
    columns <- schema$column_name
    candidate_dates <- intersect(c(
      "date", "period_end", "reference_date", "observation_period", "filing_date",
      "available_at", "retrieved_at"
    ), columns)
    start_date <- end_date <- NA_character_
    if (length(candidate_dates)) {
      date_column <- candidate_dates[[1L]]
      stats <- DBI::dbGetQuery(con, sprintf(
        "SELECT MIN(CAST(%1$s AS VARCHAR)) AS start_date, MAX(CAST(%1$s AS VARCHAR)) AS end_date FROM %2$s",
        DBI::dbQuoteIdentifier(con, date_column), DBI::dbQuoteIdentifier(con, table)
      ))
      start_date <- stats$start_date[[1L]]
      end_date <- stats$end_date[[1L]]
    }
    sample <- tryCatch(DBI::dbGetQuery(con, sprintf(
      "SELECT * FROM %s LIMIT 500", DBI::dbQuoteIdentifier(con, table)
    )), error = function(e) data.frame())
    missing_pct <- if (length(sample)) 100 * mean(is.na(sample)) else NA_real_
    frequency <- if ("native_frequency" %in% columns) {
      first_nonmissing_value(con, table, "native_frequency")
    } else {
      NA_character_
    }
    unit <- if ("unit" %in% columns) first_nonmissing_value(con, table, "unit") else NA_character_
    currency <- if ("currency" %in% columns) first_nonmissing_value(con, table, "currency") else NA_character_
    path <- upstream_path(config, record$gold_path)
    modified <- if (file.exists(path)) file.info(path)$mtime else if (dir.exists(path)) {
      max(file.info(list.files(path, recursive = TRUE, full.names = TRUE))$mtime, na.rm = TRUE)
    } else {
      as.POSIXct(NA)
    }
    data.table::data.table(
      source = record$source,
      dataset_name = record$dataset,
      file_path = record$gold_path,
      format = "parquet",
      rows = as.numeric(record$n_observations),
      columns = nrow(schema),
      start_date = as.character(start_date),
      end_date = as.character(end_date),
      frequency = frequency,
      entity_dimension = detect_dimension(columns),
      country_dimension = detect_country_dimension(columns),
      unit = unit,
      currency = currency,
      vintage_support = isTRUE(record$vintage_available),
      point_in_time_support = "available_at" %in% columns || isTRUE(record$release_lag_available),
      last_updated = as.character(modified),
      missing_pct = missing_pct,
      notes = paste0("Upstream DuckDB view: ", table, "; missingness profiled on the first <=500 rows")
    )
  })
  catalog <- data.table::rbindlist(rows, fill = TRUE)
  output_path <- project_path(output, root = config$project_root)
  write_parquet_duckdb(catalog, output_path)
  catalog
}

render_data_inventory <- function(catalog, output = "reports/data_inventory.html") {
  summary <- paste0(
    "<p><strong>", nrow(catalog), "</strong> upstream analytical datasets were inspected. ",
    "Row counts are inherited from the executed upstream catalogue; schemas, coverage fields, ",
    "and sampled missingness were re-inspected through DuckDB.</p>"
  )
  write_html_report("Financial Research Data Inventory", summary,
    list("Master catalogue" = catalog), output
  )
}
