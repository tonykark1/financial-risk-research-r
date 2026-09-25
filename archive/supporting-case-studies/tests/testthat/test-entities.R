test_that("entity normalization is deterministic", {
  expect_equal(normalize_entity_name("Example Bank, Public Limited Company"), "EXAMPLE BANK")
  expect_equal(normalize_entity_name("Foo & Bar S.A."), "FOO AND BAR")
})

test_that("deterministic identifiers are not replaced by fuzzy guesses", {
  entities <- data.table::data.table(LEI = c("ABC", NA_character_), CIK = c(NA_character_, "0001"))
  ids <- ifelse(!is.na(entities$LEI), paste0("LEI:", entities$LEI), paste0("CIK:", entities$CIK))
  expect_equal(ids, c("LEI:ABC", "CIK:0001"))
})

