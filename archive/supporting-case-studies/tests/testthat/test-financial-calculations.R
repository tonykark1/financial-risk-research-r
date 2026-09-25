test_that("safe ratios protect zero denominators", {
  expect_equal(safe_divide(c(10, 1), c(2, 0)), c(5, NA_real_))
})

test_that("accounting identity flags material breaks", {
  result <- financial_identity_check(c(100, 100), c(70, 60), c(30, 20), tolerance_pct = 0.02)
  expect_equal(result$identity_flag, c(FALSE, TRUE))
})

test_that("return and rolling calculations are backward-looking", {
  prices <- c(100, 102, 99.96)
  returns <- prices / data.table::shift(prices) - 1
  expect_equal(returns[2:3], c(0.02, -0.02), tolerance = 1e-12)
  rolled <- rolling_mean_past(1:5, width = 2, min_n = 2)
  expect_true(is.na(rolled[1]) && is.na(rolled[2]))
  expect_equal(rolled[3:5], c(1.5, 2.5, 3.5))
})

