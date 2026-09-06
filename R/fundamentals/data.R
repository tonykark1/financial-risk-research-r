fundamental_formula_dictionary <- function() {
  data.table::data.table(
    field = c("revenue", "gross_profit", "operating_income", "net_income", "cash",
      "debt", "assets", "liabilities", "equity", "operating_cash_flow", "capex",
      "interest_expense", "receivables", "inventory", "accounts_payable", "shares", "EPS"),
    source = c(rep("upstream SEC concept-priority map", 12), rep("not present in supplied normalized wide mart", 5)),
    available = c(rep(TRUE, 12), rep(FALSE, 5)),
    note = c(
      rep("Raw taxonomy, concept, unit, accession, and filing provenance remain in the upstream selected-facts mart.", 12),
      rep("Retained as an explicit coverage gap; not synthesized.", 5)
    )
  )
}

sec_instant_concepts <- function() {
  c("assets", "liabilities", "equity", "cash", "debt")
}

sec_flow_concepts <- function() {
  c("revenue", "gross_profit", "operating_income", "net_income",
    "operating_cash_flow", "capex", "interest_expense")
}

classify_sec_fact_period <- function(start_date, end_date, instant = NA_character_,
                                     standardized_concept = NA_character_) {
  start <- as_date_utc(start_date)
  end <- as_date_utc(end_date)
  instant_date <- as_date_utc(instant)
  duration <- as.integer(end - start)
  is_instant <- standardized_concept %in% sec_instant_concepts() |
    (is.na(start) & !is.na(instant_date))
  data.table::fcase(
    is_instant, "instant",
    is.finite(duration) & duration >= 70L & duration <= 110L, "quarterly",
    is.finite(duration) & duration >= 330L & duration <= 380L, "annual",
    is.finite(duration) & duration >= 111L & duration <= 329L, "ytd",
    default = "other"
  )
}

build_fundamentals_data <- function(config) {
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  wide <- upstream_path(config, "data/gold/fundamentals/company_fundamentals_wide.parquet")
  selected <- upstream_path(config, "data/gold/fundamentals/company_fundamentals_selected.parquet")
  output <- project_path("data/gold/fundamentals/company_financials.parquet",
    root = config$project_root
  )
  cutoff <- "2026-08-13"
  query <- sprintf(paste(
    "SELECT *, TRY_CAST(period_end AS DATE) AS period_end_date,",
    "TRY_CAST(available_at AS DATE) AS available_date,",
    "TRY_CAST(period_end AS DATE) IS NULL AS malformed_period_flag,",
    "TRY_CAST(available_at AS DATE) IS NULL AS malformed_available_flag,",
    "TRY_CAST(period_end AS DATE) > DATE '%s' AS future_period_flag,",
    "TRY_CAST(period_end AS DATE) > TRY_CAST(available_at AS DATE) AS period_after_filing_flag,",
    "COUNT(*) OVER (PARTITION BY CIK, period_end, available_at) > 1 AS duplicate_vintage_flag",
    "FROM read_parquet(%s)"
  ), cutoff, sql_path(wide))
  copy_query_to_parquet(con, query, output)
  normalized_output <- project_path(
    "data/gold/fundamentals/company_fundamentals_duration_normalized.parquet",
    root = config$project_root
  )
  instant_sql <- paste(sprintf("'%s'", sec_instant_concepts()), collapse = ",")
  duration_query <- sprintf(paste(
    "WITH parsed AS (SELECT *,",
    "TRY_CAST(start_date AS DATE) AS period_start_date,",
    "COALESCE(TRY_CAST(end_date AS DATE), TRY_CAST(instant AS DATE)) AS period_end_date,",
    "TRY_CAST(available_at AS DATE) AS available_date,",
    "date_diff('day', TRY_CAST(start_date AS DATE), TRY_CAST(end_date AS DATE)) AS duration_days",
    "FROM read_parquet(%s) WHERE normalized_value IS NOT NULL),",
    "classified AS (SELECT *, CASE",
    "WHEN standardized_concept IN (%s) OR (period_start_date IS NULL AND TRY_CAST(instant AS DATE) IS NOT NULL) THEN 'instant'",
    "WHEN duration_days BETWEEN 70 AND 110 THEN 'quarterly'",
    "WHEN duration_days BETWEEN 330 AND 380 THEN 'annual'",
    "WHEN duration_days BETWEEN 111 AND 329 THEN 'ytd'",
    "ELSE 'other' END AS fact_period_type",
    "FROM parsed WHERE period_end_date IS NOT NULL AND available_date IS NOT NULL),",
    "deduplicated AS (SELECT *, row_number() OVER (",
    "PARTITION BY CIK, accession, standardized_concept, period_start_date, period_end_date, available_date, unit",
    "ORDER BY CASE WHEN taxonomy='us-gaap' THEN 0 ELSE 1 END, concept, source_member) AS source_rank",
    "FROM classified)",
    "SELECT CIK, entity_name, taxonomy, concept, standardized_concept, label, unit,",
    "CAST(period_start_date AS VARCHAR) AS period_start,",
    "CAST(period_end_date AS VARCHAR) AS period_end, duration_days, fact_period_type,",
    "fact_period_type IN ('instant','quarterly','annual') AS comparison_eligible,",
    "normalized_value, form, form LIKE '%%/A' AS amendment_flag,",
    "filed, CAST(available_date AS VARCHAR) AS available_at, accession, frame,",
    "fiscal_year, fiscal_period, source_file, source_member, retrieved_at, transformation_version,",
    "'selected_fact_with_duration' AS normalization_method",
    "FROM deduplicated WHERE source_rank=1"
  ), sql_path(selected), instant_sql)
  copy_query_to_parquet(con, duration_query, normalized_output)
  dictionary <- fundamental_formula_dictionary()
  write_parquet_duckdb(dictionary, project_path("data/gold/fundamentals/field_dictionary.parquet",
    root = config$project_root
  ))
  list(financials_path = output, normalized_facts_path = normalized_output,
    dictionary = dictionary)
}

build_accounting_quality <- function(fundamentals, config) {
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  path <- fundamentals$financials_path
  tolerance <- config$fundamentals$identity_tolerance_pct
  flags_path <- project_path("data/gold/fundamentals/accounting_quality_flags.parquet",
    root = config$project_root
  )
  query <- sprintf(paste(
    "SELECT CIK, period_end, available_at,",
    "assets - liabilities - equity AS identity_difference,",
    "abs(assets - liabilities - equity) / greatest(abs(assets), abs(liabilities) + abs(equity), 1) AS identity_error_pct,",
    "coalesce(abs(assets - liabilities - equity) / greatest(abs(assets), abs(liabilities) + abs(equity), 1) > %f, false) AS identity_flag,",
    "malformed_period_flag, malformed_available_flag, future_period_flag,",
    "period_after_filing_flag, duplicate_vintage_flag,",
    "lag(revenue) OVER (PARTITION BY CIK, period_end ORDER BY available_at) AS prior_vintage_revenue,",
    "CASE WHEN lag(revenue) OVER (PARTITION BY CIK, period_end ORDER BY available_at) IS NOT NULL",
    "THEN abs(revenue - lag(revenue) OVER (PARTITION BY CIK, period_end ORDER BY available_at)) /",
    "nullif(abs(lag(revenue) OVER (PARTITION BY CIK, period_end ORDER BY available_at)), 0) END AS restatement_change_pct",
    "FROM read_parquet(%s)"
  ), tolerance, sql_path(path))
  copy_query_to_parquet(con, query, flags_path)
  summary <- data.table::as.data.table(DBI::dbGetQuery(con, sprintf(paste(
    "SELECT COUNT(*) AS records, COUNT(DISTINCT CIK) AS companies,",
    "SUM(CAST(identity_flag AS INTEGER)) AS identity_flags,",
    "SUM(CAST(future_period_flag AS INTEGER)) AS future_period_flags,",
    "SUM(CAST(period_after_filing_flag AS INTEGER)) AS period_after_filing_flags,",
    "SUM(CAST(duplicate_vintage_flag AS INTEGER)) AS duplicate_vintage_flags,",
    "SUM(CAST(restatement_change_pct > 0.1 AS INTEGER)) AS large_restatement_flags",
    "FROM read_parquet(%s)"
  ), sql_path(flags_path))))
  list(flags_path = flags_path, summary = summary)
}
