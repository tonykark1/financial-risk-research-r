read_demo_inputs <- function(config) {
  root <- config$fixture_directory
  list(
    macro = data.table::fread(file.path(root, "macro_fixture.csv")),
    bank = data.table::fread(file.path(root, "bank_fixture.csv")),
    fundamentals = data.table::fread(file.path(root, "fundamentals_fixture.csv"))
  )
}

run_demo_macro <- function(data, config) {
  dt <- data.table::as.data.table(data.table::copy(data))
  assert_schema_contract(dt, c("date", "target_available_date_5d", "log_forward_rv_5d",
    "log_har_daily", "log_har_weekly", "log_har_monthly", "log_vix"), "demo macro")
  dt[, `:=`(date = as_date_utc(date), target_available_date_5d = as_date_utc(target_available_date_5d))]
  data.table::setorder(dt, date)
  split <- floor(nrow(dt) * config$macro_initial_fraction)
  test_start <- dt$date[[split + 1L]]
  train <- dt[seq_len(split)][target_available_date_5d < test_start]
  test <- dt[seq.int(split + 1L, nrow(dt))]
  validate_chronological_split(train$date, test$date)
  if (any(train$target_available_date_5d >= test_start)) stop("Demo target leakage")
  formulas <- list(
    HAR = log_forward_rv_5d ~ log_har_daily + log_har_weekly + log_har_monthly,
    HAR_VIX = log_forward_rv_5d ~ log_har_daily + log_har_weekly + log_har_monthly + log_vix
  )
  metrics <- data.table::rbindlist(lapply(names(formulas), function(model) {
    fit <- stats::lm(formulas[[model]], data = train)
    prediction <- as.numeric(stats::predict(fit, newdata = test))
    actual_variance <- exp(test$log_forward_rv_5d)
    predicted_variance <- exp(prediction)
    data.table::data.table(
      Model = model, Forecasts = sum(is.finite(prediction)),
      QLIKE = qlike(actual_variance, predicted_variance),
      RMSE = rmse(actual_variance, predicted_variance)
    )
  }))
  list(metrics = metrics, train_rows = nrow(train), test_rows = nrow(test),
    test_start = test_start)
}

summarize_demo_bank <- function(data) {
  dt <- data.table::as.data.table(data.table::copy(data))
  assert_schema_contract(dt, c("bank_id", "quarter", "CET1_model", "overall_risk_score",
    "availability_date_method", "point_in_time_status"), "demo bank")
  dt[, quarter := as_date_utc(quarter)]
  latest <- dt[quarter == max(quarter, na.rm = TRUE)][order(-overall_risk_score)]
  list(
    coverage = data.table::data.table(
      Banks = data.table::uniqueN(dt$bank_id), Periods = data.table::uniqueN(dt$quarter),
      `PIT status` = unique(dt$point_in_time_status)[[1L]],
      `Supported dimensions` = "capital; profitability"
    ),
    ranking = latest[, .(Bank = bank_name, Country = country,
      `CET1 (%)` = round(100 * CET1_model, 2),
      `Monitoring score` = round(overall_risk_score, 3))][1:min(.N, 10)]
  )
}

summarize_demo_fundamentals <- function(data) {
  dt <- data.table::as.data.table(data.table::copy(data))
  assert_schema_contract(dt, c("CIK", "frequency", "fiscal_year", "fiscal_period",
    "kpi", "value", "normalization_method"), "demo fundamentals")
  dt[, .(
    Records = .N, Companies = data.table::uniqueN(CIK),
    KPIs = data.table::uniqueN(kpi),
    `Normalization methods` = data.table::uniqueN(normalization_method)
  ), by = .(Frequency = frequency)]
}

write_demo_report <- function(macro, bank, fundamentals, config) {
  dir.create(config$output_directory, recursive = TRUE, showWarnings = FALSE)
  summary <- paste(
    "Fast, offline demonstration of the same research contracts used by the full pipeline:",
    "chronological target gating, conservative bank timing labels, and duration-separated SEC KPIs.",
    "Fixtures are deterministic samples; scale claims belong to the full executed pipeline."
  )
  write_html_report("Financial Research in R - Five-Minute Demo", summary, list(
    "Macro out-of-sample comparison" = macro$metrics,
    "Bank scope and timing" = bank$coverage,
    "Illustrative bank monitoring ranking" = bank$ranking,
    "Duration-aware fundamentals coverage" = fundamentals
  ), file.path(config$output_directory, "portfolio_demo.html"))
}
