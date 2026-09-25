test_that("macro schema contracts fail loudly", {
  x <- data.table::data.table(
    date = as.Date("2024-01-02"),
    rv_1d = 0.01,
    log_vix = 3
  )
  expect_true(assert_schema_contract(x, c("date", "rv_1d", "log_vix"), "macro"))
  expect_error(
    assert_schema_contract(x, c("date", "rv_1d", "available_date"), "macro"),
    "available_date"
  )
})
