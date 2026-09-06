get_information_set <- function(data, as_of_date, datasets = NULL,
                                available_col = "available_at",
                                observation_col = "observation_date",
                                dataset_col = "dataset_name",
                                key_cols = NULL) {
  dt <- data.table::as.data.table(data.table::copy(data))
  checkmate::assert_names(names(dt), must.include = available_col)
  cutoff <- as_date_utc(as_of_date)
  dt[, .available_date__ := as_date_utc(get(available_col))]
  dt <- dt[!is.na(.available_date__) & .available_date__ <= cutoff]
  if (!is.null(datasets)) {
    checkmate::assert_names(names(dt), must.include = dataset_col)
    dt <- dt[get(dataset_col) %chin% datasets]
  }
  if (!is.null(key_cols) && nrow(dt)) {
    order_cols <- c(key_cols, observation_col, ".available_date__")
    order_cols <- order_cols[order_cols %in% names(dt)]
    data.table::setorderv(dt, order_cols, rep(1L, length(order_cols)), na.last = TRUE)
    dt <- dt[, .SD[.N], by = key_cols]
  }
  dt[, .available_date__ := NULL]
  dt[]
}

pit_join <- function(x, y, observation_date, available_date, by,
                     x_date = "as_of_date", allow_exact = TRUE) {
  obs_col <- observation_date
  avail_col <- available_date
  asof_col <- x_date
  left <- data.table::as.data.table(data.table::copy(x))
  right <- data.table::as.data.table(data.table::copy(y))
  required_left <- c(by, x_date)
  required_right <- c(by, observation_date, available_date)
  checkmate::assert_names(names(left), must.include = required_left)
  checkmate::assert_names(names(right), must.include = required_right)
  left[, .pit_row__ := .I]
  left[, .pit_asof__ := as_date_utc(get(asof_col))]
  right[, .pit_obs__ := as_date_utc(get(obs_col))]
  right[, .pit_available__ := as_date_utc(get(avail_col))]
  candidates <- merge(left, right, by = by, all.x = TRUE, allow.cartesian = TRUE,
    suffixes = c("", ".y")
  )
  comparator <- if (allow_exact) {
    candidates$.pit_obs__ <= candidates$.pit_asof__ &
      candidates$.pit_available__ <= candidates$.pit_asof__
  } else {
    candidates$.pit_obs__ < candidates$.pit_asof__ &
      candidates$.pit_available__ < candidates$.pit_asof__
  }
  candidates <- candidates[is.na(.pit_obs__) | comparator]
  data.table::setorder(candidates, .pit_row__, -.pit_obs__, -.pit_available__, na.last = TRUE)
  result <- candidates[, .SD[1L], by = .pit_row__]
  data.table::setorder(result, .pit_row__)
  result[, c(".pit_row__", ".pit_asof__", ".pit_obs__", ".pit_available__") := NULL]
  result[]
}

assert_no_future_information <- function(data, forecast_date = "forecast_date",
                                         available_date = "available_at",
                                         training_end = NULL) {
  dt <- data.table::as.data.table(data)
  forecast <- as_date_utc(dt[[forecast_date]])
  available <- as_date_utc(dt[[available_date]])
  bad <- !is.na(forecast) & !is.na(available) & available > forecast
  if (any(bad)) stop(sum(bad), " record(s) contain future-release leakage")
  if (!is.null(training_end) && "training_date" %in% names(dt)) {
    train <- as_date_utc(dt$training_date)
    if (any(train > as_date_utc(training_end), na.rm = TRUE)) {
      stop("Training data extend beyond the declared training end")
    }
  }
  invisible(TRUE)
}
