robust_z <- function(x, center = NULL, scale = NULL) {
  center <- center %||% stats::median(x, na.rm = TRUE)
  scale <- scale %||% stats::mad(x, center = center, constant = 1.4826, na.rm = TRUE)
  if (!is.finite(scale) || scale <= .Machine$double.eps) return(rep(NA_real_, length(x)))
  (x - center) / scale
}

percentile_score <- function(x, higher_is_worse = TRUE) {
  score <- data.table::frank(x, ties.method = "average", na.last = "keep") /
    sum(!is.na(x))
  if (higher_is_worse) score else 1 - score
}

expanding_z <- function(x, min_n = 20L) {
  out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) {
    history <- x[seq_len(i - 1L)]
    history <- history[is.finite(history)]
    if (length(history) >= min_n) {
      s <- stats::sd(history)
      if (is.finite(s) && s > 0) out[[i]] <- (x[[i]] - mean(history)) / s
    }
  }
  out
}

rmse <- function(actual, predicted) sqrt(mean((actual - predicted)^2, na.rm = TRUE))
mae <- function(actual, predicted) mean(abs(actual - predicted), na.rm = TRUE)

oos_r_squared <- function(actual, predicted, benchmark) {
  1 - sum((actual - predicted)^2, na.rm = TRUE) /
    sum((actual - benchmark)^2, na.rm = TRUE)
}

qlike <- function(actual_variance, predicted_variance, epsilon = 1e-12) {
  actual <- pmax(actual_variance, epsilon)
  predicted <- pmax(predicted_variance, epsilon)
  mean(log(predicted) + actual / predicted, na.rm = TRUE)
}

rolling_mean_past <- function(x, width, min_n = width) {
  slider::slide_dbl(data.table::shift(x), ~ {
    z <- .x[is.finite(.x)]
    if (length(z) < min_n) NA_real_ else mean(z)
  }, .before = width - 1L, .complete = FALSE)
}

