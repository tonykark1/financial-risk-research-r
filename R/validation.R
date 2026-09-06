duplicate_key_flags <- function(data, keys) {
  dt <- data.table::as.data.table(data.table::copy(data))
  checkmate::assert_names(names(dt), must.include = keys)
  dt[, duplicate_count := .N, by = keys]
  dt[, duplicate_flag := duplicate_count > 1L]
  dt[]
}

flag_ratio_bounds <- function(x, lower = -Inf, upper = Inf) {
  !is.na(x) & (!is.finite(x) | x < lower | x > upper)
}

flag_scale_jump <- function(x, threshold = 10) {
  prior <- data.table::shift(abs(x))
  ratio <- pmax(abs(x), prior, na.rm = TRUE) / pmax(pmin(abs(x), prior, na.rm = TRUE), 1e-12)
  !is.na(ratio) & ratio >= threshold
}

financial_identity_check <- function(assets, liabilities, equity, tolerance_pct = 0.02) {
  difference <- assets - liabilities - equity
  scale <- pmax(abs(assets), abs(liabilities) + abs(equity), 1)
  data.table::data.table(
    identity_difference = difference,
    identity_error_pct = abs(difference) / scale,
    identity_flag = is.finite(difference) & abs(difference) / scale > tolerance_pct
  )
}

validate_chronological_split <- function(train_dates, test_dates) {
  train <- as_date_utc(train_dates)
  test <- as_date_utc(test_dates)
  if (!length(train) || !length(test)) stop("Training and test windows must be non-empty")
  if (max(train, na.rm = TRUE) >= min(test, na.rm = TRUE)) {
    stop("Chronological split violation: training reaches the test window")
  }
  invisible(TRUE)
}

assert_schema_contract <- function(data, required_columns, dataset = "dataset") {
  missing <- setdiff(required_columns, names(data))
  if (length(missing)) {
    stop(dataset, " schema contract failed; missing columns: ", paste(missing, collapse = ", "))
  }
  invisible(TRUE)
}

quality_summary <- function(flags, dataset, check_name, severity = "warning") {
  data.table::data.table(
    dataset = dataset,
    check = check_name,
    severity = if (sum(flags, na.rm = TRUE) > 0L) severity else "ok",
    count = sum(flags, na.rm = TRUE),
    checked_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )
}
