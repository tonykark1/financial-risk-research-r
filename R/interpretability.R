extract_feature_importance <- function(fitted) {
  predictors <- fitted$predictors
  if (fitted$model %in% c("Ridge", "Elastic_Net")) {
    coefficient <- as.numeric(stats::coef(fitted$fit))[-1L]
    return(data.table::data.table(feature = predictors, importance = abs(coefficient),
      signed_effect = coefficient))
  }
  if (fitted$model == "Random_Forest") {
    importance <- fitted$fit$variable.importance
    return(data.table::data.table(feature = names(importance), importance = as.numeric(importance),
      signed_effect = NA_real_))
  }
  if (fitted$model == "XGBoost") {
    importance <- xgboost::xgb.importance(feature_names = predictors, model = fitted$fit)
    feature_column <- intersect(c("Feature", "Features"), names(importance))[[1L]]
    return(data.table::data.table(feature = importance[[feature_column]], importance = importance$Gain,
      signed_effect = NA_real_))
  }
  coefficient <- fitted$fit$coefficients[-1L]
  data.table::data.table(feature = predictors, importance = abs(coefficient), signed_effect = coefficient)
}

run_macro_feature_stability <- function(macro_data, config, horizon = 22L) {
  panel <- define_macro_regimes(macro_data$panel, config$macro_vol$initial_window_days)
  target <- paste0("log_forward_rv_", horizon, "d")
  available <- paste0("target_available_date_", horizon, "d")
  panel <- panel[is.finite(get(target)) & !is.na(get(available))]
  dates <- stats::quantile(as.numeric(panel$date), c(0.6, 0.8, 1), na.rm = TRUE)
  cutoffs <- as.Date(dates, origin = "1970-01-01")
  sets <- macro_predictor_sets(panel)
  models <- c("Ridge", "Elastic_Net", "Random_Forest", "XGBoost")
  rows <- list()
  k <- 0L
  for (cutoff in cutoffs) {
    train <- panel[date <= cutoff & get(available) <= cutoff]
    for (model in models) {
      k <- k + 1L
      fitted <- fit_forecast_model(train, target, sets[[model]], model,
        seed = config$seed + k
      )
      importance <- extract_feature_importance(fitted)
      importance[, `:=`(model = model, horizon = horizon, training_end = cutoff)]
      rows[[k]] <- importance
    }
  }
  result <- data.table::rbindlist(rows, fill = TRUE)
  result[, stability_rank := data.table::frank(-importance), by = .(model, training_end)]
  write_parquet_duckdb(result, project_path("data/gold/macro_vol/feature_stability.parquet",
    root = config$project_root
  ))
  result[]
}

run_bank_feature_importance <- function(features, config) {
  target <- "future_CET1_deterioration_1q"
  available <- "target_quarter_1q"
  predictors <- bank_predictors(features)
  dates <- stats::quantile(as.numeric(features$quarter), c(0.7, 1), na.rm = TRUE)
  cutoffs <- as.Date(dates, origin = "1970-01-01")
  models <- c("Ridge", "Elastic_Net", "Random_Forest", "XGBoost")
  rows <- list()
  k <- 0L
  for (cutoff in cutoffs) {
    train <- features[quarter <= cutoff & get(available) <= cutoff & is.finite(get(target))]
    for (model in models) {
      k <- k + 1L
      fitted <- fit_forecast_model(train, target, predictors, model, seed = config$seed + k)
      importance <- extract_feature_importance(fitted)
      importance[, `:=`(model = model, horizon = 1L, training_end = cutoff)]
      rows[[k]] <- importance
    }
  }
  result <- data.table::rbindlist(rows, fill = TRUE)
  write_parquet_duckdb(result, project_path("data/gold/bank_risk/feature_importance.parquet",
    root = config$project_root
  ))
  result[]
}
