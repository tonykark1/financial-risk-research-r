test_that("future releases are excluded from information sets", {
  x <- data.table::data.table(
    series_id = c("GDP", "GDP"), observation_date = as.Date(c("2019-03-31", "2019-03-31")),
    value = c(1, 2), available_at = as.Date(c("2019-04-30", "2019-07-30"))
  )
  got <- get_information_set(x, "2019-06-14", key_cols = c("series_id", "observation_date"))
  expect_equal(got$value, 1)
})

test_that("point-in-time joins select the newest visible observation", {
  forecasts <- data.table::data.table(series_id = "GDP", as_of_date = as.Date(c("2019-05-15", "2019-08-15")))
  releases <- data.table::data.table(
    series_id = "GDP", observation_date = as.Date(c("2019-03-31", "2019-06-30")),
    available_at = as.Date(c("2019-04-30", "2019-07-30")), value = c(1, 2)
  )
  got <- pit_join(forecasts, releases, "observation_date", "available_at", by = "series_id")
  expect_equal(got$value, c(1, 2))
  expect_true(assert_no_future_information(
    data.table::data.table(forecast_date = got$as_of_date, available_at = got$available_at)
  ))
})

test_that("future information triggers an explicit failure", {
  bad <- data.table::data.table(
    forecast_date = as.Date("2020-01-01"), available_at = as.Date("2020-01-02")
  )
  expect_error(assert_no_future_information(bad), "future-release leakage")
})

