test_that("schema contracts fail loudly when a required field disappears", {
  x <- data.table::data.table(CIK = "1", period_end = "2024-12-31")
  expect_true(assert_schema_contract(x, c("CIK", "period_end"), "fundamentals"))
  expect_error(
    assert_schema_contract(x, c("CIK", "period_end", "available_at"), "fundamentals"),
    "available_at"
  )
})
