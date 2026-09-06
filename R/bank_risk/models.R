bank_predictors <- function(data) {
  intersect(c("CET1_model", "Tier1_model", "total_capital_model",
    "leverage_ratio_model", "RWA_density", "ROA", "capital_deterioration",
    "asset_growth", "RWA_growth", "ROA_change"), names(data)
  )
}

run_bank_models <- function(features, config) {
  dt <- data.table::copy(features)
  predictors <- bank_predictors(dt)
  models <- c("Pooled_OLS", "Bank_FE_OLS", "Ridge", "Elastic_Net", "Random_Forest", "XGBoost")
  results <- list()
  k <- 0L
  quarters <- sort(unique(dt$quarter))
  for (horizon in config$bank_risk$horizons_quarters) {
    target <- paste0("future_CET1_deterioration_", horizon, "q")
    target_quarter <- paste0("target_quarter_", horizon, "q")
    for (test_quarter in quarters[seq.int(config$bank_risk$minimum_training_quarters + 1L, length(quarters))]) {
      train <- dt[quarter < test_quarter & get(target_quarter) < test_quarter & is.finite(get(target))]
      test <- dt[quarter == test_quarter & is.finite(get(target))]
      if (nrow(train) < 100L || !nrow(test)) next
      prep <- training_preprocessor(train, predictors)
      for (model in models) {
        k <- k + 1L
        if (model == "Pooled_OLS") {
          fitted <- fit_forecast_model(train, target, predictors, "OLS", seed = config$seed + k)
          prediction <- predict_forecast_model(fitted, test)
          params <- "{}"
        } else if (model == "Bank_FE_OLS") {
          formula <- stats::as.formula(paste(target, "~", paste(predictors, collapse = "+"), "| bank_id"))
          fitted <- fixest::feols(formula, data = train, warn = FALSE, notes = FALSE)
          prediction <- as.numeric(stats::predict(fitted, newdata = test))
          params <- jsonlite::toJSON(list(fixed_effect = "bank_id"), auto_unbox = TRUE)
        } else {
          fitted <- fit_forecast_model(train, target, predictors, model, seed = config$seed + k)
          prediction <- predict_forecast_model(fitted, test)
          params <- jsonlite::toJSON(fitted$hyperparameters, auto_unbox = TRUE)
        }
        results[[k]] <- data.table::data.table(
          bank_id = test$bank_id, country = test$country, model, horizon,
          training_start = min(train$quarter), training_end = max(train$quarter),
          forecast_quarter = test_quarter, actual = test[[target]], prediction,
          benchmark_prediction = 0, hyperparameters = params, n_train = nrow(train)
        )
      }
    }
  }
  predictions <- data.table::rbindlist(results, fill = TRUE)
  metrics <- predictions[is.finite(prediction), .(
    forecasts = .N, RMSE = rmse(actual, prediction), MAE = mae(actual, prediction),
    R2_OOS = oos_r_squared(actual, prediction, benchmark_prediction),
    rank_correlation = suppressWarnings(stats::cor(actual, prediction,
      method = "spearman", use = "complete.obs"))
  ), by = .(model, horizon)]
  metrics[, rank_RMSE := data.table::frank(RMSE), by = horizon]
  write_parquet_duckdb(predictions, project_path("data/gold/bank_risk/model_predictions.parquet",
    root = config$project_root
  ))
  write_parquet_duckdb(metrics, project_path("data/gold/bank_risk/model_metrics.parquet",
    root = config$project_root
  ))
  list(predictions = predictions, metrics = metrics)
}

run_bank_stress_scenarios <- function(features, macro_data, config) {
  macro <- data.table::copy(macro_data$panel)
  macro[, quarter := period_to_date(paste0(format(date, "%Y"), sprintf("%02d", ((as.integer(format(date, "%m")) - 1L) %/% 3L + 1L) * 3L)))]
  quarterly <- macro[, .(
    policy_rate = tail(DFF[is.finite(DFF)], 1L),
    sovereign_yield = tail(DGS10[is.finite(DGS10)], 1L),
    credit_spread = tail(BAMLH0A0HYM2[is.finite(BAMLH0A0HYM2)], 1L),
    vix = tail(vix[is.finite(vix)], 1L),
    GDP = tail(GDPC1[is.finite(GDPC1)], 1L)
  ), by = quarter]
  quarterly[, `:=`(
    policy_rate_change = policy_rate - data.table::shift(policy_rate),
    sovereign_yield_change = sovereign_yield - data.table::shift(sovereign_yield),
    credit_spread_change = credit_spread - data.table::shift(credit_spread),
    vix_change_pct = vix / data.table::shift(vix) - 1,
    GDP_growth = GDP / data.table::shift(GDP) - 1
  )]
  panel <- merge(features, quarterly, by = "quarter", all.x = TRUE, suffixes = c("", ".macro"))
  panel[, cet1_change := CET1_model - data.table::shift(CET1_model), by = bank_id]
  regressors <- c("policy_rate_change", "sovereign_yield_change", "credit_spread_change", "vix_change_pct", "GDP_growth")
  estimation <- panel[is.finite(cet1_change)]
  coefficients <- stats::setNames(vapply(regressors, function(regressor) {
    sample <- estimation[is.finite(get(regressor))]
    if (nrow(sample) < 100L || data.table::uniqueN(sample[[regressor]]) < 3L) return(NA_real_)
    formula <- stats::as.formula(paste("cet1_change ~", regressor, "+ factor(bank_id)"))
    fit <- stats::lm(formula, data = sample)
    value <- stats::coef(fit)[[regressor]]
    if (is.finite(value)) value else NA_real_
  }, numeric(1)), regressors)
  beta <- function(name) {
    value <- if (name %in% names(coefficients)) unname(coefficients[[name]]) else NA_real_
    if (is.finite(value)) value else NA_real_
  }
  scenarios <- data.table::data.table(
    scenario = c("Rates +100bp", "Sovereign yields +150bp", "Macro GDP -2%", "Market volatility +50%"),
    policy_rate_change = c(1, 0, 0, 0), sovereign_yield_change = c(0, 1.5, 0, 0),
    credit_spread_change = c(0, 0, 0, 0), GDP_growth = c(0, 0, -0.02, 0),
    vix_change_pct = c(0, 0, 0, 0.5)
  )
  contribution <- function(coefficient, shock) {
    data.table::fifelse(shock == 0, 0, coefficient * shock)
  }
  scenarios[, estimated_cet1_change :=
    contribution(beta("policy_rate_change"), policy_rate_change) +
      contribution(beta("sovereign_yield_change"), sovereign_yield_change) +
      contribution(beta("credit_spread_change"), credit_spread_change) +
      contribution(beta("GDP_growth"), GDP_growth) +
      contribution(beta("vix_change_pct"), vix_change_pct)]
  scenarios[, estimable := is.finite(estimated_cet1_change)]
  latest <- panel[quarter == max(quarter, na.rm = TRUE)]
  base <- latest[, .(bank_id, bank_name, country, quarter, CET1 = CET1_model,
    overall_risk_score)]
  base[, join_key__ := 1L]
  scenarios[, join_key__ := 1L]
  stressed <- merge(base, scenarios, by = "join_key__", allow.cartesian = TRUE)
  stressed[, join_key__ := NULL]
  stressed[, stressed_CET1 := CET1 + estimated_cet1_change]
  stressed[, vulnerability_rank := data.table::frank(stressed_CET1,
    ties.method = "min", na.last = "keep"), by = scenario]
  write_parquet_duckdb(stressed, project_path("data/gold/bank_risk/stress_scenarios.parquet",
    root = config$project_root
  ))
  list(results = stressed, coefficients = coefficients, n_estimation = nrow(estimation))
}
