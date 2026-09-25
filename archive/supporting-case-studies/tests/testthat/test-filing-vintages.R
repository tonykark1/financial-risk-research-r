test_that("filing-vintage selection never uses later restatements", {
  filings <- data.table::data.table(
    CIK = "0001", period_end = as.Date("2023-12-31"),
    available_at = as.Date(c("2024-02-01", "2024-05-01")),
    revenue = c(100, 90), accession = c("original", "amendment")
  )
  historical <- select_filing_vintage(filings, "2024-03-01")
  current <- select_filing_vintage(filings, "2024-06-01")
  expect_equal(historical$accession, "original")
  expect_equal(current$accession, "amendment")
})

