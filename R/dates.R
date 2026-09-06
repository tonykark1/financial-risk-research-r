as_date_utc <- function(x) {
  if (inherits(x, "Date")) return(x)
  if (inherits(x, "POSIXt")) return(as.Date(x, tz = "UTC"))
  out <- rep(as.Date(NA), length(x))
  if (is.numeric(x) || is.integer(x)) {
    plausible_days <- is.finite(x) & x > -20000 & x < 200000
    out[plausible_days] <- as.Date(x[plausible_days], origin = "1970-01-01")
    return(out)
  }
  value <- trimws(as.character(x))
  value[value %in% c("", "NA", "NaT", "None")] <- NA_character_
  formats <- c("%Y-%m-%d", "%Y/%m/%d", "%Y-%m-%dT%H:%M:%S", "%Y%m%d")
  for (fmt in formats) {
    missing <- is.na(out) & !is.na(value)
    if (!any(missing)) break
    parsed <- as.Date(strptime(substr(value[missing], 1L, 19L), format = fmt, tz = "UTC"))
    out[which(missing)] <- parsed
  }
  out
}

period_to_date <- function(x) {
  value <- gsub("[^0-9Qq]", "", as.character(x))
  out <- rep(as.Date(NA), length(value))
  is_quarter <- grepl("^[0-9]{4}[Qq][1-4]$", value)
  if (any(is_quarter)) {
    year <- as.integer(substr(value[is_quarter], 1, 4))
    quarter <- as.integer(substr(value[is_quarter], 6, 6))
    month <- quarter * 3L
    first_next <- as.Date(sprintf("%04d-%02d-01", year + (month == 12L), (month %% 12L) + 1L))
    out[is_quarter] <- first_next - 1L
  }
  is_month <- grepl("^[0-9]{6}$", value)
  if (any(is_month)) {
    year <- as.integer(substr(value[is_month], 1, 4))
    month <- as.integer(substr(value[is_month], 5, 6))
    valid <- month %in% 1:12
    idx <- which(is_month)[valid]
    first_next <- as.Date(sprintf("%04d-%02d-01",
      year[valid] + (month[valid] == 12L), (month[valid] %% 12L) + 1L
    ))
    out[idx] <- first_next - 1L
  }
  is_year <- grepl("^[0-9]{4}$", value)
  if (any(is_year)) out[is_year] <- as.Date(paste0(value[is_year], "-12-31"))
  out
}

quarter_id <- function(x) {
  date <- as_date_utc(x)
  q <- (as.integer(format(date, "%m")) - 1L) %/% 3L + 1L
  paste0(format(date, "%Y"), "Q", q)
}
