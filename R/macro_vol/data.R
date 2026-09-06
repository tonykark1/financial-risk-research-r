build_forward_variance_targets <- function(data, horizons = c(1L, 5L, 10L, 22L)) {
  dt <- data.table::as.data.table(data.table::copy(data))
  data.table::setorder(dt, date)
  for (horizon in horizons) {
    future_components <- lapply(seq_len(horizon), function(k) {
      data.table::shift(dt$rv_1d, n = k, type = "lead")
    })
    matrix <- do.call(cbind, future_components)
    complete <- rowSums(is.finite(matrix)) == horizon
    target <- rep(NA_real_, nrow(dt))
    target[complete] <- rowSums(matrix[complete, , drop = FALSE])
    dt[, paste0("forward_rv_", horizon, "d") := target]
    dt[, paste0("log_forward_rv_", horizon, "d") := log(pmax(target, 1e-12))]
    dt[, paste0("target_available_date_", horizon, "d") :=
      data.table::shift(date, n = horizon, type = "lead")]
  }
  dt[]
}

asof_macro_series <- function(forecast_dates, macro, series) {
  values <- macro[series_id == series & !is.na(available_date) & !is.na(observation_date)]
  if (!nrow(values)) {
    return(data.table::data.table(date = forecast_dates, series_id = series,
      value = NA_real_, source_available_date = as.Date(NA), observation_date = as.Date(NA)
    ))
  }
  data.table::setorder(values, available_date, observation_date)
  values <- values[, .SD[.N], by = available_date]
  data.table::setkey(values, available_date)
  grid <- data.table::data.table(as_of_date = forecast_dates)
  values[grid, on = .(available_date <= as_of_date), mult = "last", .(
    date = i.as_of_date,
    series_id = series,
    value = normalized_value,
    source_available_date = x.available_date,
    observation_date = x.observation_date
  )]
}

build_macro_forecast_panel <- function(config, instrument = "^GSPC") {
  con <- upstream_connection(config)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  rv <- data.table::as.data.table(DBI::dbGetQuery(con, sprintf(
    paste(
      "SELECT CAST(date AS DATE) AS date, log_return, rv_1d, har_daily,",
      "har_weekly, har_monthly FROM macro_forecasting__realized_volatility",
      "WHERE instrument_id = '%s' ORDER BY date"
    ), gsub("'", "''", instrument, fixed = TRUE)
  )))
  vix <- data.table::as.data.table(DBI::dbGetQuery(con, paste(
    "SELECT CAST(date AS DATE) AS date, adjusted_close AS vix",
    "FROM macro_forecasting__market_daily WHERE instrument_id = '^VIX'"
  )))
  selected_series <- c(
    "DFF", "DGS2", "DGS10", "T10Y2Y", "BAMLH0A0HYM2", "VIXCLS",
    "UNRATE", "CPIAUCSL", "INDPRO", "GDPC1"
  )
  series_sql <- paste(sprintf("'%s'", selected_series), collapse = ",")
  macro <- data.table::as.data.table(DBI::dbGetQuery(con, sprintf(
    paste(
      "SELECT series_id, CAST(coalesce(date, observation_period) AS DATE) AS observation_date,",
      "CAST(available_at AS DATE) AS available_date, normalized_value",
      "FROM macro_forecasting__macro_vintages_long",
      "WHERE vintage_available = true AND series_id IN (%s)",
      "AND normalized_value IS NOT NULL"
    ), series_sql
  )))
  macro_long <- data.table::rbindlist(lapply(selected_series, function(series) {
    asof_macro_series(rv$date, macro, series)
  }))
  leakage <- macro_long[!is.na(source_available_date) & source_available_date > date]
  if (nrow(leakage)) stop("Macro as-of join admitted future releases")
  macro_wide <- data.table::dcast(macro_long, date ~ series_id, value.var = "value")
  panel <- merge(rv, vix, by = "date", all.x = TRUE)
  panel <- merge(panel, macro_wide, by = "date", all.x = TRUE)
  data.table::setorder(panel, date)
  panel[, curve_slope := DGS10 - DGS2]
  panel[, credit_spread_change_22d := BAMLH0A0HYM2 - data.table::shift(BAMLH0A0HYM2, 22L)]
  panel[, policy_rate_change_63d := DFF - data.table::shift(DFF, 63L)]
  panel[, equity_drawdown_22d := exp(cumsum(data.table::fifelse(is.na(log_return), 0, log_return))) /
    data.table::frollmax(exp(cumsum(data.table::fifelse(is.na(log_return), 0, log_return))), 22L, align = "right") - 1]
  panel[, `:=`(
    log_har_daily = log(pmax(har_daily, 1e-12)),
    log_har_weekly = log(pmax(har_weekly, 1e-12)),
    log_har_monthly = log(pmax(har_monthly, 1e-12)),
    log_vix = log(pmax(vix, 1e-8))
  )]
  panel <- build_forward_variance_targets(panel, config$macro_vol$horizons_days)
  start <- as.Date("2005-07-01")
  panel <- panel[date >= start]
  output <- project_path("data/gold/macro_vol/forecast_panel.parquet", root = config$project_root)
  write_parquet_duckdb(panel, output)
  list(panel = panel, macro_asof = macro_long, selected_series = selected_series)
}

build_macro_vintage_coverage <- function(macro_data, config) {
  coverage <- macro_data$macro_asof[!is.na(source_available_date), .(
    forecast_dates_covered = data.table::uniqueN(date),
    distinct_visible_releases = data.table::uniqueN(source_available_date),
    first_observation = min(observation_date, na.rm = TRUE),
    last_observation = max(observation_date, na.rm = TRUE),
    first_available = min(source_available_date, na.rm = TRUE),
    last_available = max(source_available_date, na.rm = TRUE),
    median_release_lag_days = stats::median(as.numeric(source_available_date - observation_date), na.rm = TRUE),
    true_vintage_primary = TRUE,
    revised_history_admitted = FALSE
  ), by = series_id]
  path <- project_path("data/gold/macro_vol/vintage_coverage.parquet",
    root = config$project_root)
  write_parquet_duckdb(coverage, path)
  coverage[]
}

define_macro_regimes <- function(panel, initial_window = 756L) {
  dt <- data.table::as.data.table(data.table::copy(panel))
  calibration <- dt[seq_len(min(initial_window, nrow(dt)))]
  vix_threshold <- stats::quantile(calibration$vix, 0.75, na.rm = TRUE)
  spread_threshold <- stats::quantile(calibration$credit_spread_change_22d, 0.75, na.rm = TRUE)
  drawdown_threshold <- stats::quantile(calibration$equity_drawdown_22d, 0.25, na.rm = TRUE)
  dt[, `:=`(
    high_vix = vix >= vix_threshold,
    rapid_tightening = policy_rate_change_63d >= 1,
    credit_spread_widening = credit_spread_change_22d >= spread_threshold,
    equity_drawdown = equity_drawdown_22d <= drawdown_threshold,
    inflation_shock = CPIAUCSL / data.table::shift(CPIAUCSL, 252L) - 1 >= 0.04,
    growth_slowdown = INDPRO / data.table::shift(INDPRO, 252L) - 1 <= 0
  )]
  attr(dt, "thresholds") <- list(
    vix = as.numeric(vix_threshold), spread_change = as.numeric(spread_threshold),
    drawdown = as.numeric(drawdown_threshold)
  )
  dt[]
}
