test_that("mixed dates and reporting periods are parsed", {
  expect_equal(as_date_utc(c("2024-01-02", "20240103")), as.Date(c("2024-01-02", "2024-01-03")))
  expect_equal(period_to_date(c("2024Q1", "202406")), as.Date(c("2024-03-31", "2024-06-30")))
  expect_equal(quarter_id(as.Date("2024-05-05")), "2024Q2")
})

