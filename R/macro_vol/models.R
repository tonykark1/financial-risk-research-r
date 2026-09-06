macro_predictor_sets <- function(panel) {
  base <- c("log_har_daily", "log_har_weekly", "log_har_monthly")
  full <- c(base, "log_vix", "DFF", "DGS2", "DGS10", "curve_slope",
    "BAMLH0A0HYM2", "UNRATE", "CPIAUCSL", "INDPRO", "GDPC1"
  )
  full <- intersect(full, names(panel))
  list(
    HAR = base,
    HAR_VIX = c(base, "log_vix"),
    HAR_Rates = c(base, "DFF", "DGS10", "curve_slope"),
    Ridge = full,
    Elastic_Net = full,
    Random_Forest = full,
    XGBoost = full
  )
}

run_macro_model_suite <- function(macro_data, config) {
  panel <- define_macro_regimes(macro_data$panel, config$macro_vol$initial_window_days)
  sets <- macro_predictor_sets(panel)
  results <- list()
  k <- 0L
  for (horizon in config$macro_vol$horizons_days) {
    target <- paste0("log_forward_rv_", horizon, "d")
    available <- paste0("target_available_date_", horizon, "d")
    model_data <- panel[!is.na(get(target)) & !is.na(get(available))]
    for (model in names(sets)) {
      k <- k + 1L
      frequency <- if (model %in% c("Random_Forest", "XGBoost")) {
        config$macro_vol$ml_retrain_frequency_days
      } else {
        config$macro_vol$retrain_frequency_days
      }
      results[[k]] <- run_walk_forward(
        model_data, target = target, predictors = sets[[model]], model = model,
        horizon = horizon, initial_window = config$macro_vol$initial_window_days,
        retrain_frequency = frequency, tuning = TRUE,
        target_available_col = available, seed = config$seed
      )
    }
  }
  predictions <- data.table::rbindlist(results, fill = TRUE)
  predictions[, `:=`(
    actual_variance = exp(actual),
    predicted_variance = exp(prediction)
  )]
  output <- project_path("data/gold/macro_vol/walk_forward_predictions.parquet",
    root = config$project_root
  )
  write_parquet_duckdb(predictions, output)
  list(predictions = predictions, panel = panel, predictor_sets = sets)
}

dm_hac_test <- function(actual, forecast_a, forecast_b, horizon = 1L) {
  loss_a <- log(pmax(forecast_a, 1e-12)) + actual / pmax(forecast_a, 1e-12)
  loss_b <- log(pmax(forecast_b, 1e-12)) + actual / pmax(forecast_b, 1e-12)
  differential <- loss_a - loss_b
  differential <- differential[is.finite(differential)]
  if (length(differential) < 30L) return(data.table::data.table(statistic = NA_real_, p_value = NA_real_))
  fit <- stats::lm(differential ~ 1)
  covariance <- sandwich::NeweyWest(fit, lag = max(0L, horizon - 1L), prewhite = FALSE, adjust = TRUE)
  test <- lmtest::coeftest(fit, vcov. = covariance)
  data.table::data.table(statistic = unname(test[1, "t value"]), p_value = unname(test[1, "Pr(>|t|)"]))
}

evaluate_macro_models <- function(model_suite, config) {
  predictions <- data.table::copy(model_suite$predictions)
  metrics <- predictions[is.finite(actual_variance) & is.finite(predicted_variance), .(
    forecasts = .N,
    QLIKE = qlike(actual_variance, predicted_variance),
    log_MSE = mean((actual - prediction)^2),
    RMSE = rmse(actual_variance, predicted_variance),
    MAE = mae(actual_variance, predicted_variance)
  ), by = .(model, horizon)]
  metrics[, rank_QLIKE := data.table::frank(QLIKE, ties.method = "min"), by = horizon]
  har <- predictions[model == "HAR", .(horizon, forecast_date, har_prediction = predicted_variance)]
  comparisons <- merge(predictions, har, by = c("horizon", "forecast_date"), all.x = TRUE)
  dm <- comparisons[model != "HAR", {
    test <- dm_hac_test(actual_variance, predicted_variance, har_prediction, horizon[[1L]])
    .(statistic = test$statistic, p_value = test$p_value)
  }, by = .(model, horizon)]
  regime_columns <- c("high_vix", "rapid_tightening", "credit_spread_widening",
    "equity_drawdown", "inflation_shock", "growth_slowdown"
  )
  regimes <- data.table::melt(model_suite$panel[, c("date", regime_columns), with = FALSE],
    id.vars = "date", variable.name = "regime", value.name = "active"
  )[active == TRUE]
  regime_predictions <- merge(predictions, regimes, by.x = "forecast_date", by.y = "date",
    allow.cartesian = TRUE
  )
  regime_metrics <- regime_predictions[is.finite(predicted_variance), .(
    forecasts = .N, QLIKE = qlike(actual_variance, predicted_variance)
  ), by = .(regime, model, horizon)]
  write_parquet_duckdb(metrics, project_path("data/gold/macro_vol/model_metrics.parquet",
    root = config$project_root
  ))
  write_parquet_duckdb(dm, project_path("data/gold/macro_vol/dm_tests.parquet",
    root = config$project_root
  ))
  write_parquet_duckdb(regime_metrics, project_path("data/gold/macro_vol/regime_metrics.parquet",
    root = config$project_root
  ))
  list(metrics = metrics, dm_tests = dm, regime_metrics = regime_metrics)
}
