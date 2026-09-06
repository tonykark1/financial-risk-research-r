bank_metric_suffixes <- function() {
  c(
    CET1 = "0140", Tier1 = "0141", total_capital = "0142",
    CET1_fully_loaded = "0146", leverage_ratio = "0905",
    RWA = "0138", total_assets = "1010", profit_after_tax = "0333"
  )
}

build_bank_quarterly_panel <- function(config) {
  con <- upstream_connection(config)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  suffixes <- bank_metric_suffixes()
  metric_sql <- paste(vapply(names(suffixes), function(metric) {
    sprintf(
      "median(normalized_value) FILTER (WHERE right(item, 4) = '%s') AS %s",
      suffixes[[metric]], metric
    )
  }, character(1)), collapse = ",\n")
  sql <- sprintf(paste(
    "SELECT LEI AS bank_id, LEI, any_value(bank_name) AS bank_name,",
    "any_value(country) AS country, observation_period, %s",
    "FROM bank_risk__bank_quarterly_panel",
    "WHERE right(item, 4) IN (%s)",
    "GROUP BY LEI, observation_period"
  ), metric_sql, paste(sprintf("'%s'", suffixes), collapse = ","))
  panel <- data.table::as.data.table(DBI::dbGetQuery(con, sql))
  bank_reference <- data.table::as.data.table(DBI::dbGetQuery(con, sprintf(
    "SELECT LEI, any_value(bank_name) AS mapped_bank_name, any_value(country) AS mapped_country FROM read_parquet(%s) GROUP BY LEI",
    sql_path(upstream_path(config, "catalog/bank_identifier_crosswalk.parquet"))
  )))
  panel <- merge(panel, bank_reference, by = "LEI", all.x = TRUE)
  panel[, bank_name := data.table::fcoalesce(bank_name, mapped_bank_name)]
  panel[, country := data.table::fcoalesce(country, mapped_country)]
  panel[, c("mapped_bank_name", "mapped_country") := NULL]
  panel[, quarter := period_to_date(observation_period)]
  panel[, available_at := quarter + 120L]
  panel[, availability_date_estimated := TRUE]
  panel[, `:=`(
    availability_date_method = "quarter_end_plus_120_days",
    point_in_time_status = "conservative_pseudo_pit"
  )]
  data.table::setorder(panel, bank_id, quarter)
  ratio_columns <- c("CET1", "Tier1", "total_capital", "CET1_fully_loaded", "leverage_ratio")
  for (column in ratio_columns) {
    panel[, paste0(column, "_impossible_flag") := flag_ratio_bounds(get(column), 0, 1)]
    panel[, paste0(column, "_model") := data.table::fifelse(
      get(paste0(column, "_impossible_flag")), NA_real_, get(column)
    )]
  }
  panel[, RWA_density := safe_divide(RWA, total_assets)]
  panel[, ROA := safe_divide(profit_after_tax, total_assets)]
  panel[, `:=`(
    NPL_ratio = NA_real_, NPE_ratio = NA_real_, coverage_ratio = NA_real_,
    loan_growth = NA_real_, deposit_growth = NA_real_, ROE = NA_real_,
    NIM = NA_real_, cost_income_ratio = NA_real_, sovereign_exposure = NA_real_,
    mortgage_exposure = NA_real_, corporate_exposure = NA_real_,
    market_cap = NA_real_, daily_equity_vol = NA_real_, beta = NA_real_,
    drawdown = NA_real_, downside_beta = NA_real_, country_GDP_growth = NA_real_,
    unemployment = NA_real_, inflation = NA_real_, policy_rate = NA_real_,
    yield_curve = NA_real_, sovereign_yield = NA_real_, credit_spread = NA_real_
  )]
  panel[, `:=`(
    capital_deterioration = data.table::shift(CET1_model) - CET1_model,
    asset_growth = total_assets / data.table::shift(total_assets) - 1,
    RWA_growth = RWA / data.table::shift(RWA) - 1,
    ROA_change = ROA - data.table::shift(ROA)
  ), by = bank_id]
  panel[, `:=`(
    capital_available = !is.na(CET1_model) | !is.na(leverage_ratio_model),
    credit_available = FALSE,
    profitability_available = !is.na(ROA),
    market_available = FALSE,
    macro_available = FALSE
  )]
  output <- project_path("data/gold/bank_risk/bank_quarterly_panel.parquet",
    root = config$project_root
  )
  write_parquet_duckdb(panel, output)
  panel[]
}

bank_data_quality <- function(panel, config) {
  dt <- data.table::copy(panel)
  duplicate <- duplicated(dt, by = c("bank_id", "quarter"))
  dt[, missing_bank_id_flag := is.na(bank_id) | !nzchar(bank_id)]
  dt[, capital_jump_flag := abs(CET1_model - data.table::shift(CET1_model)) > 0.05, by = bank_id]
  dt[, rwa_jump_flag := abs(RWA / data.table::shift(RWA) - 1) > 0.5, by = bank_id]
  dt[, asset_scale_jump_flag := flag_scale_jump(total_assets), by = bank_id]
  dt[, missing_period_flag := as.integer(quarter - data.table::shift(quarter)) > 190L, by = bank_id]
  summaries <- data.table::rbindlist(list(
    quality_summary(duplicate, "bank_quarterly_panel", "duplicate_bank_quarter"),
    quality_summary(dt$missing_bank_id_flag, "bank_quarterly_panel", "missing_bank_id"),
    quality_summary(rowSums(dt[, grep("impossible_flag$", names(dt), value = TRUE), with = FALSE], na.rm = TRUE) > 0,
      "bank_quarterly_panel", "impossible_ratio"),
    quality_summary(dt$capital_jump_flag, "bank_quarterly_panel", "capital_ratio_jump"),
    quality_summary(dt$rwa_jump_flag, "bank_quarterly_panel", "rwa_jump"),
    quality_summary(dt$asset_scale_jump_flag, "bank_quarterly_panel", "asset_scale_jump"),
    quality_summary(dt$missing_period_flag, "bank_quarterly_panel", "missing_reporting_period")
  ))
  flags_path <- project_path("data/gold/bank_risk/data_quality_flags.parquet", root = config$project_root)
  write_parquet_duckdb(dt, flags_path)
  list(flagged_panel = dt, summary = summaries)
}
