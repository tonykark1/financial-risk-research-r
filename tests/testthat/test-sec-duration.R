test_that("SEC fact durations are classified without mixing frequencies", {
  got <- classify_sec_fact_period(
    start_date = c(NA, "2024-01-01", "2024-01-01", "2024-01-01", "2024-01-01"),
    end_date = c("2024-03-31", "2024-03-31", "2024-12-31", "2024-09-30", "2024-02-01"),
    instant = c("2024-03-31", NA, NA, NA, NA),
    standardized_concept = c("assets", rep("revenue", 4))
  )
  expect_equal(got, c("instant", "quarterly", "annual", "ytd", "other"))
})

test_that("balance concepts remain instant even when a start date is present", {
  got <- classify_sec_fact_period("2024-01-01", "2024-03-31", "2024-03-31", "equity")
  expect_equal(got, "instant")
})

test_that("first-filed policy is deterministic and ignores later amendments", {
  x <- data.table::data.table(
    CIK = "1", frequency = "annual", fiscal_year = 2023L, fiscal_period = "FY",
    available_at = c("2024-03-10", "2024-02-20", "2024-02-20"),
    accession = c("late", "b", "a"), value = c(3, 2, 1)
  )
  got <- select_first_filed_vintage(x)
  expect_equal(got$accession, "a")
  expect_equal(got$value, 1)
})
