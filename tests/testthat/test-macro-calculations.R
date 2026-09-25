test_that("safe ratios protect zero denominators", {
  expect_equal(safe_divide(c(10, 1), c(2, 0)), c(5, NA_real_))
})

test_that("return and rolling calculations are backward-looking", {
  prices <- c(100, 102, 99.96)
  returns <- prices / data.table::shift(prices) - 1
  expect_equal(returns[2:3], c(0.02, -0.02), tolerance = 1e-12)
  rolled <- rolling_mean_past(1:5, width = 2, min_n = 2)
  expect_true(is.na(rolled[1]) && is.na(rolled[2]))
  expect_equal(rolled[3:5], c(1.5, 2.5, 3.5))
})

test_that("QLIKE prefers a closer positive variance forecast", {
  actual <- c(0.01, 0.04, 0.09)
  close <- c(0.011, 0.039, 0.088)
  far <- c(0.10, 0.10, 0.10)
  expect_lt(qlike(actual, close), qlike(actual, far))
})
