normalize_entity_name <- function(x) {
  value <- iconv(toupper(as.character(x)), to = "ASCII//TRANSLIT")
  value <- gsub("&", " AND ", value, fixed = TRUE)
  value <- gsub("[^A-Z0-9 ]+", " ", value)
  value <- gsub("\\b(PUBLIC LIMITED COMPANY|LIMITED|LTD|PLC|S A|SA|AG|SPA|NV|BV|INC|CORP|CORPORATION|LLC)\\b", " ", value)
  trimws(gsub("\\s+", " ", value))
}

read_sec_ticker_master <- function(config) {
  path <- upstream_path(config, "data/raw/sec_company_tickers.json")
  raw <- jsonlite::fromJSON(path, simplifyDataFrame = TRUE)
  dt <- data.table::rbindlist(raw, fill = TRUE)
  data.table::setnames(dt, intersect(c("cik_str", "title"), names(dt)),
    intersect(c("CIK", "entity_name"), c("CIK", "entity_name"))[seq_len(length(intersect(c("cik_str", "title"), names(dt))))]
  )
  if ("CIK" %in% names(dt)) dt[, CIK := sprintf("%010d", as.integer(CIK))]
  dt[]
}

build_entity_layer <- function(config) {
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  bank_path <- upstream_path(config, "catalog/bank_identifier_crosswalk.parquet")
  filings_path <- upstream_path(config, "data/gold/fundamentals/filing_metadata.parquet")
  banks <- data.table::as.data.table(DBI::dbGetQuery(con, sprintf(
    paste(
      "SELECT LEI, bank_name, country, ISIN, first_period, last_period,",
      "mapping_provenance, CAST(mapping_confidence AS DOUBLE) AS mapping_confidence",
      "FROM read_parquet(%s)"
    ), sql_path(bank_path)
  )))
  companies <- data.table::as.data.table(DBI::dbGetQuery(con, sprintf(
    paste(
      "SELECT CIK, any_value(entity_name) AS entity_name,",
      "MIN(filing_date) AS first_filing, MAX(filing_date) AS last_filing",
      "FROM read_parquet(%s) GROUP BY CIK"
    ), sql_path(filings_path)
  )))
  tickers <- read_sec_ticker_master(config)
  if (all(c("CIK", "ticker") %in% names(tickers))) {
    companies <- merge(companies, tickers[, .(CIK, ticker)], by = "CIK", all.x = TRUE)
  } else {
    companies[, ticker := NA_character_]
  }
  bank_entities <- banks[, .(
    legal_name = bank_name,
    normalized_name = normalize_entity_name(bank_name),
    LEI, EBA_ID = NA_character_, CIK = NA_character_, ISIN,
    ticker = NA_character_, exchange = NA_character_, MIC = NA_character_, country,
    parent = NA_character_, listed_flag = NA,
    valid_from = as.character(period_to_date(first_period)),
    valid_to = as.character(period_to_date(last_period)),
    mapping_method = mapping_provenance,
    mapping_confidence = as.numeric(mapping_confidence)
  )]
  company_entities <- companies[, .(
    legal_name = entity_name,
    normalized_name = normalize_entity_name(entity_name),
    LEI = NA_character_, EBA_ID = NA_character_, CIK, ISIN = NA_character_,
    ticker, exchange = NA_character_, MIC = NA_character_, country = NA_character_,
    parent = NA_character_, listed_flag = !is.na(ticker),
    valid_from = first_filing, valid_to = last_filing,
    mapping_method = ifelse(!is.na(ticker), "SEC deterministic CIK-ticker", "SEC deterministic CIK"),
    mapping_confidence = 1
  )]
  entity_master <- data.table::rbindlist(list(bank_entities, company_entities), fill = TRUE)
  entity_master[, entity_id := fifelse(!is.na(LEI), paste0("LEI:", LEI), paste0("CIK:", CIK))]
  data.table::setcolorder(entity_master, c("entity_id", setdiff(names(entity_master), "entity_id")))
  crosswalk <- data.table::melt(
    entity_master,
    id.vars = c("entity_id", "legal_name", "mapping_method", "mapping_confidence", "valid_from", "valid_to"),
    measure.vars = c("LEI", "EBA_ID", "CIK", "ISIN", "ticker", "MIC"),
    variable.name = "identifier_type", value.name = "identifier",
    variable.factor = FALSE, na.rm = TRUE
  )
  crosswalk <- crosswalk[nzchar(identifier)]
  entity_path <- project_path("data/gold/entity_master.parquet", root = config$project_root)
  crosswalk_path <- project_path("data/gold/identifier_crosswalk.parquet", root = config$project_root)
  write_parquet_duckdb(entity_master, entity_path)
  write_parquet_duckdb(crosswalk, crosswalk_path)
  list(entity_master = entity_master, crosswalk = crosswalk)
}

render_entity_mapping_report <- function(entity_layer, output = "reports/entity_mapping_report.html") {
  entities <- entity_layer$entity_master
  banks <- entities[!is.na(LEI)]
  summary_table <- data.table::data.table(
    metric = c("EBA/bank entities", "LEI coverage", "ISIN coverage", "Ticker coverage", "SEC companies", "SEC ticker coverage"),
    value = c(
      nrow(banks), mean(!is.na(banks$LEI)), mean(!is.na(banks$ISIN)), mean(!is.na(banks$ticker)),
      sum(!is.na(entities$CIK)), mean(!is.na(entities$ticker[!is.na(entities$CIK)]))
    )
  )
  unmatched <- banks[is.na(ISIN) | is.na(ticker), .(legal_name, LEI, country, ISIN, ticker)]
  write_html_report("Entity Mapping Report",
    "<p>Deterministic identifiers are retained as the primary mapping method. Missing tickers and CIKs are reported, not guessed from names or debt-security ISINs.</p>",
    list("Coverage" = summary_table, "Unmatched or incomplete bank mappings" = unmatched), output
  )
}

