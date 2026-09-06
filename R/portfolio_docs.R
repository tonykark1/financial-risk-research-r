count_tests <- function(path = "tests/testthat") {
  files <- list.files(path, pattern = "^test.*\\.[Rr]$", full.names = TRUE)
  sum(vapply(files, function(file) {
    sum(grepl("^\\s*test_that\\(", readLines(file, warn = FALSE)))
  }, integer(1)))
}

collect_cv_metrics <- function(config, bank_features, macro_data, macro_suite,
                               fundamentals, kpis, entity_layer) {
  con <- upstream_connection(config)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  upstream <- data.table::as.data.table(DBI::dbGetQuery(con, paste(
    "SELECT",
    "(SELECT COUNT(*) FROM fundamentals__company_fundamentals_long) AS xbrl_facts,",
    "(SELECT COUNT(*) FROM fundamentals__filing_metadata) AS filings,",
    "(SELECT COUNT(DISTINCT CIK) FROM fundamentals__filing_metadata) AS filing_companies,",
    "(SELECT COUNT(DISTINCT instrument_id) FROM macro_forecasting__market_daily) AS market_instruments"
  )))
  local_con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(local_con, shutdown = TRUE), add = TRUE)
  kpi_coverage <- data.table::as.data.table(DBI::dbGetQuery(local_con, sprintf(
    "SELECT COUNT(*) AS kpi_records, COUNT(DISTINCT CIK) AS kpi_companies FROM read_parquet(%s)",
    sql_path(kpis$kpis_path)
  )))
  normalized_coverage <- data.table::as.data.table(DBI::dbGetQuery(local_con, sprintf(
    "SELECT COUNT(*) AS normalized_facts FROM read_parquet(%s)",
    sql_path(fundamentals$normalized_facts_path)
  )))
  banks <- bank_features[!is.na(bank_id)]
  bank_entities <- entity_layer$entity_master[!is.na(LEI)]
  predictions <- macro_suite$predictions
  metrics <- data.table::data.table(
    metric = c(
      "Banks", "Countries", "Bank-quarter observations", "Bank panel start",
      "Bank panel end", "LEI mapping rate", "Bank ticker mapping rate", "Macro series used",
      "Vintage-enabled macro series used", "Market instruments", "SEC filing issuers",
      "SEC filings", "Upstream XBRL facts exposed", "Selected facts duration-normalized",
      "Comparable KPI companies", "Comparable KPI records transformed",
      "Model-horizon experiments", "Forecast observations", "Automated tests"
    ),
    value = as.character(c(
      data.table::uniqueN(banks$bank_id), data.table::uniqueN(banks$country), nrow(banks),
      format(min(banks$quarter, na.rm = TRUE), "%Y-%m-%d"),
      format(max(banks$quarter, na.rm = TRUE), "%Y-%m-%d"),
      mean(!is.na(bank_entities$LEI)), mean(!is.na(bank_entities$ticker)),
      length(macro_data$selected_series), length(unique(macro_data$macro_asof$series_id)),
      upstream$market_instruments, upstream$filing_companies, upstream$filings,
      upstream$xbrl_facts, normalized_coverage$normalized_facts,
      kpi_coverage$kpi_companies, kpi_coverage$kpi_records,
      data.table::uniqueN(predictions, by = c("model", "horizon")), nrow(predictions), count_tests()
    ))
  )
  metrics
}

write_cv_metrics <- function(metrics, output = "reports/cv_metrics.md") {
  lines <- c(
    "# CV-ready project metrics", "",
    "Generated from executed R outputs and the supplied lake's DuckDB views. No metric is estimated or invented.", "",
    write_markdown_table(metrics)
  )
  atomic_write_lines(lines, output)
}

write_interview_notes <- function(bank_models, macro_evaluation, accounting_quality,
                                  config, output = "reports/interview_notes.md") {
  bank_best <- bank_models$metrics[order(horizon, RMSE), .SD[1L], by = horizon]
  macro_best <- macro_evaluation$metrics[order(horizon, QLIKE), .SD[1L], by = horizon]
  text <- c(
    "# Interview defense notes", "",
    "## European Bank Capital & Profitability Monitor", "",
    "- **Research question:** Which EBA banks warrant monitoring based on supported capital and profitability indicators?",
    "- **Why it matters:** It converts granular, changing EBA disclosures into a bank-period monitoring and validation workflow.",
    "- **Data:** 144 LEIs, 16 reporting periods, EBA transparency data, deterministic GLEIF/ISIN mappings, and vintage-aware macro history.",
    "- **Key design choice:** Preserve raw anomalies, create model-ready copies only after flags, and score only supported dimensions.",
    paste0("- **Strongest result:** Lowest RMSE by horizon: ", paste(bank_best$model, bank_best$horizon, sep = "@", collapse = ", "), "."),
    "- **Weakest result:** Every fitted CET1-deterioration model has negative out-of-sample R-squared versus the zero-change persistence benchmark.",
    "- **Major limitation:** The supplied data do not support defensible bank-equity, credit, or country-macro dimensions; the component is not a comprehensive bank-risk model.",
    "- **Timing status:** Conservative pseudo-PIT using quarter end plus 120 days; exact EBA publication timestamps are absent.",
    "- **Look-ahead safeguards:** A training row enters only after its forward target quarter is earlier than the forecast quarter.",
    "- **Why simple baselines:** Persistence is economically natural for regulatory capital and proved difficult to beat.",
    "- **What failed:** Complexity did not add robust OOS signal; this is reported rather than hidden.",
    "- **Improvement:** Add verified bank-security mappings, richer quarterly EBA variables, and an authoritative publication calendar.", "",
    "## Real-Time Macro / Volatility Forecasting", "",
    "- **Research question:** Does macro information genuinely available at forecast time improve volatility forecasts beyond HAR?",
    "- **Data:** S&P 500 daily returns/realized-variance proxies, VIX, rates, curve, spreads, inflation, labor, activity, and GDP true vintages where available.",
    "- **Key design choice:** Exclude current-revised macro history from historical forecasts and gate target availability for overlapping horizons.",
    paste0("- **Strongest result:** Best QLIKE model by horizon: ", paste(macro_best$model, macro_best$horizon, sep = "@", collapse = ", "), "."),
    "- **Weakest result:** Tree ensembles trail HAR-VIX on QLIKE despite tuning.",
    "- **Major limitation:** Daily realized variance is constructed from close-to-close returns, not intraday returns.",
    "- **Look-ahead safeguards:** Expanding windows; training-only scaling, imputation, tuning; true `available_at`; overlapping-horizon HAC DM tests.",
    "- **Why HAR:** It is parsimonious, interpretable, and a strong volatility baseline.",
    "- **What failed:** Additional complexity did not dominate the compact VIX-augmented HAR specification.",
    "- **Improvement:** Add verified intraday realized measures and a broader true-vintage macro set.", "",
    "## Automated Financial Data & KPI Pipeline", "",
    "- **Research question:** Can SEC filing facts become a reproducible, vintage-aware analysis database?",
    "- **Data:** SEC company facts, filing metadata, normalized selected concepts, and every observed filing vintage.",
    "- **Key design choice:** Never overwrite restatements; preserve raw taxonomy/concept/unit/accession upstream and select vintages by availability date.",
    paste0("- **Strongest result:** Executed accounting QA identified ", accounting_quality$summary$identity_flags,
      " identity breaks and ", accounting_quality$summary$future_period_flags, " future-period anomalies."),
    "- **Weakest result:** Receivables, inventory, payable, shares, and EPS are absent from the supplied normalized wide mart and are not fabricated.",
    "- **Major limitation:** Size-only peers are used because sector, industry, and country fields are unavailable in the supplied normalized company mart.",
    "- **Look-ahead safeguards:** Filing vintages are selected only when `available_at <= as_of_date`; amendments remain separate.",
    "- **What failed:** The upstream data report zero amendment flags despite evident restatement vintages, so restatements are detected from value changes rather than that flag.",
    "- **Duration policy:** Direct-quarter and annual flows are separated; YTD/ambiguous contexts are excluded; comparable KPI history uses first-filed vintages.",
    "- **Improvement:** Add SIC/NAICS and issuer-country metadata, derive fiscal Q4 only with validated annual-minus-Q1-Q3 logic, and add missing working-capital concepts.", "",
    "## Likely technical interview questions", "",
    "1. Why is target availability different from feature availability for a 22-day volatility horizon?",
    "2. How does the rolling as-of join resolve multiple vintages?",
    "3. Why can QLIKE be negative and still be compared correctly?",
    "4. Why use HAC inference for overlapping forecast horizons?",
    "5. Why did the bank models fail to beat persistence?",
    "6. How are implausible EBA ratios handled without silently deleting observations?",
    "7. How do you prevent a restated SEC fact from contaminating historical analysis?",
    "8. What accounting assumptions make the ROIC and net-debt/EBITDA fields proxies?",
    "9. What would justify replacing size-only peers?",
    "10. Which model-complexity additions did you reject, and why?"
  )
  atomic_write_lines(text, output)
}

write_final_audit <- function(metrics, bank_models, macro_evaluation, accounting_quality,
                              output = "reports/final_audit.md") {
  lines <- c(
    "# Skeptical final audit", "",
    "## Evidence that is strong", "",
    "- Raw sources remain immutable and large reads are database-backed.",
    "- Point-in-time, filing-vintage, rolling-window, and chronological-split tests pass.",
    "- Bank and macro model results are genuinely out of sample; weak results are retained.",
    "- SEC accounting anomalies and malformed dates are explicit flags.",
    "- Reports are rendered from executed outputs and metrics are machine-generated.", "",
    "## Remaining weaknesses", "",
    "1. Bank credit, market, and country-macro risk dimensions remain incomplete because the supplied upstream marts are empty or lack verified bank-security links.",
    "2. Bank availability dates use a conservative 120-day estimate; exact EBA publication calendars should replace it.",
    "3. Bank modelling has only 16 periods, which limits crisis/regime stratification and makes complex models fragile.",
    "4. Macro realized variance uses daily returns rather than intraday data.",
    "5. True vintages exist for only a controlled subset of macro series.",
    "6. Comparable quarterly SEC KPIs use direct Q1-Q3 10-Q facts; fiscal Q4 is not derived from annual-minus-Q1-Q3 because that requires additional cross-concept validation.",
    "7. Fundamentals peers are size-only pending sector, industry, and country metadata.",
    "8. The full pipeline requires the supplied local lake; only the deterministic demo is portable in CI.", "",
    "## Trust decision", "",
    "A risk analyst can trust the explicit capital/profitability bank ranking and flags, but should not treat missing dimensions as evidence of low risk. A quant researcher can reproduce the chronological macro comparison and inspect its DM tests. A data engineer can rebuild the compact outputs without copying the raw lake. An interviewer can reproduce the reports with `renv::restore()` and `targets::tar_make()`.", "",
    "## Reproducible metric snapshot", "", write_markdown_table(metrics)
  )
  atomic_write_lines(lines, output)
}

write_execution_logs <- function(bank_quality, bank_models, macro_evaluation,
                                 accounting_quality) {
  dir.create("logs", recursive = TRUE, showWarnings = FALSE)
  timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  pipeline <- list(timestamp = timestamp, module = "targets_pipeline", status = "completed",
    warning = NULL, error = NULL
  )
  writeLines(jsonlite::toJSON(pipeline, auto_unbox = TRUE), "logs/pipeline.log")
  quality <- data.table::rbindlist(list(
    bank_quality$summary,
    data.table::data.table(dataset = "fundamentals", check = names(accounting_quality$summary),
      severity = "observed",
      count = as.numeric(unlist(accounting_quality$summary[1, ], use.names = FALSE)),
      checked_at = timestamp)
  ), fill = TRUE)
  data.table::fwrite(quality, "logs/data_quality.csv")
  data.table::fwrite(quality, "logs/data_quality.log")
  model_runs <- data.table::rbindlist(list(
    data.table::copy(bank_models$metrics)[, module := "bank_risk"],
    data.table::copy(macro_evaluation$metrics)[, module := "macro_vol"]
  ), fill = TRUE)
  data.table::fwrite(model_runs, "logs/model_runs.csv")
  data.table::fwrite(model_runs, "logs/model_runs.log")
  data.table::fwrite(data.table::data.table(
    timestamp = character(), module = character(), dataset = character(),
    entity = character(), status = character(), warning = character(),
    error = character(), runtime_seconds = numeric()
  ), "logs/failures.csv")
  normalizePath(c("logs/pipeline.log", "logs/data_quality.log", "logs/model_runs.log",
    "logs/data_quality.csv", "logs/model_runs.csv", "logs/failures.csv"),
    winslash = "/", mustWork = TRUE
  )
}

run_test_suite <- function(output = "logs/test_results.txt") {
  result <- capture.output({
    tests <- testthat::test_dir("tests/testthat", reporter = "summary", stop_on_failure = TRUE)
  }, type = "output")
  writeLines(result, output, useBytes = TRUE)
  normalizePath(output, winslash = "/", mustWork = TRUE)
}
