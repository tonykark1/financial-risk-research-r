test_that("walk-forward splits exclude unobserved future targets", {
  dates <- seq(as.Date("2020-01-01"), by = "day", length.out = 20)
  available <- dates + 2L
  splits <- walk_forward_splits(dates, available, initial_window = 10, retrain_frequency = 3)
  for (split in splits) {
    expect_true(all(dates[split$train] < split$forecast_date))
    expect_true(all(available[split$train] < split$forecast_date))
  }
  expect_true(splits[[1]]$retrain)
  expect_false(splits[[2]]$retrain)
})

test_that("training-window preprocessing does not use test values", {
  train <- data.table::data.table(x = 1:100)
  prep <- training_preprocessor(train, "x")
  expect_equal(unname(prep$medians), 50.5)
  transformed <- apply_preprocessor(data.table::data.table(x = NA_real_), "x", prep)
  expect_equal(as.numeric(transformed), 0)
})
