test_that("duplicate keys and chronological overlap are detected", {
  x <- data.table::data.table(id = c(1, 1), date = as.Date(c("2020-01-01", "2020-01-01")))
  flagged <- duplicate_key_flags(x, c("id", "date"))
  expect_true(all(flagged$duplicate_flag))
  expect_error(
    validate_chronological_split(as.Date(c("2020-01-01", "2020-01-02")), as.Date("2020-01-02")),
    "violation"
  )
})

