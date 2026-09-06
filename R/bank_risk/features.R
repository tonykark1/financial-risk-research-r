score_bank_risk <- function(panel, config) {
  dt <- data.table::copy(panel)
  dt[, `:=`(
    cet1_risk_z = -robust_z(CET1_model),
    leverage_risk_z = -robust_z(leverage_ratio_model),
    rwa_density_risk_z = robust_z(RWA_density),
    deterioration_risk_z = robust_z(capital_deterioration),
    roa_risk_z = -robust_z(ROA),
    roa_change_risk_z = -robust_z(ROA_change)
  ), by = quarter]
  dt[, capital_risk_score := rowMeans(.SD, na.rm = TRUE),
    .SDcols = c("cet1_risk_z", "leverage_risk_z", "rwa_density_risk_z", "deterioration_risk_z")]
  dt[, profitability_risk_score := rowMeans(.SD, na.rm = TRUE),
    .SDcols = c("roa_risk_z", "roa_change_risk_z")]
  dt[!is.finite(capital_risk_score), capital_risk_score := NA_real_]
  dt[!is.finite(profitability_risk_score), profitability_risk_score := NA_real_]
  dt[, `:=`(
    credit_risk_score = NA_real_, market_risk_score = NA_real_, macro_risk_score = NA_real_
  )]
  dimensions <- c("capital_risk_score", "credit_risk_score", "profitability_risk_score",
    "market_risk_score", "macro_risk_score"
  )
  dt[, overall_risk_score := rowMeans(.SD, na.rm = TRUE), .SDcols = dimensions]
  dt[!is.finite(overall_risk_score), overall_risk_score := NA_real_]
  weights <- c(capital_risk_score = 0.35, credit_risk_score = 0.25,
    profitability_risk_score = 0.15, market_risk_score = 0.15, macro_risk_score = 0.10
  )
  dt[, overall_risk_score_economic := {
    values <- unlist(.SD)
    available <- is.finite(values)
    if (!any(available)) NA_real_ else sum(values[available] * weights[names(values)[available]]) /
      sum(weights[names(values)[available]])
  }, by = seq_len(nrow(dt)), .SDcols = dimensions]
  dt[, overall_risk_percentile := percentile_score(overall_risk_score), by = quarter]
  for (horizon in config$bank_risk$horizons_quarters) {
    dt[, paste0("future_CET1_deterioration_", horizon, "q") :=
      CET1_model - data.table::shift(CET1_model, n = horizon, type = "lead"), by = bank_id]
    dt[, paste0("future_ROA_deterioration_", horizon, "q") :=
      ROA - data.table::shift(ROA, n = horizon, type = "lead"), by = bank_id]
    dt[, paste0("target_quarter_", horizon, "q") :=
      data.table::shift(quarter, n = horizon, type = "lead"), by = bank_id]
  }
  output <- project_path("data/gold/bank_risk/bank_risk_features.parquet",
    root = config$project_root
  )
  write_parquet_duckdb(dt, output)
  dt[]
}

