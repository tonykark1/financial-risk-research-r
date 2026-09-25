read_demo_input <- function(config) {
  data.table::fread(file.path(config$fixture_directory, "macro_fixture.csv"))
}

run_demo_macro <- function(data, config) {
  dt <- data.table::as.data.table(data.table::copy(data))
  assert_schema_contract(dt, c(
    "date", "target_available_date_5d", "log_forward_rv_5d",
    "log_har_daily", "log_har_weekly", "log_har_monthly", "log_vix"
  ), "demo macro")
  dt[, `:=`(
    date = as_date_utc(date),
    target_available_date_5d = as_date_utc(target_available_date_5d)
  )]
  data.table::setorder(dt, date)
  split <- floor(nrow(dt) * config$macro_initial_fraction)
  test_start <- dt$date[[split + 1L]]
  train <- dt[seq_len(split)][target_available_date_5d < test_start]
  test <- dt[seq.int(split + 1L, nrow(dt))]
  validate_chronological_split(train$date, test$date)
  if (any(train$target_available_date_5d >= test_start)) stop("Demo target leakage")

  formulas <- list(
    HAR = log_forward_rv_5d ~ log_har_daily + log_har_weekly + log_har_monthly,
    HAR_VIX = log_forward_rv_5d ~ log_har_daily + log_har_weekly +
      log_har_monthly + log_vix
  )
  metrics <- data.table::rbindlist(lapply(names(formulas), function(model) {
    fit <- stats::lm(formulas[[model]], data = train)
    prediction <- as.numeric(stats::predict(fit, newdata = test))
    actual_variance <- exp(test$log_forward_rv_5d)
    predicted_variance <- exp(prediction)
    data.table::data.table(
      Model = model,
      Forecasts = sum(is.finite(prediction)),
      QLIKE = qlike(actual_variance, predicted_variance),
      RMSE = rmse(actual_variance, predicted_variance)
    )
  }))
  list(
    metrics = metrics,
    train_rows = nrow(train),
    test_rows = nrow(test),
    test_start = test_start
  )
}

write_demo_report <- function(macro, config) {
  dir.create(config$output_directory, recursive = TRUE, showWarnings = FALSE)
  summary <- paste(
    "A deterministic, offline check of the public research contract:",
    "targets are admitted only after their forecast horizon has elapsed,",
    "the split is chronological, and HAR is compared with HAR plus VIX.",
    "The fixture is illustrative and does not reproduce the full 127,218 saved forecasts."
  )
  write_html_report(
    "Point-in-Time Volatility Research - Five-Minute Demo",
    summary,
    list(
      "Out-of-sample comparison" = macro$metrics,
      "Split audit" = data.table::data.table(
        `Training rows` = macro$train_rows,
        `Test rows` = macro$test_rows,
        `Test starts` = as.character(macro$test_start)
      )
    ),
    file.path(config$output_directory, "macro_demo.html")
  )
}
