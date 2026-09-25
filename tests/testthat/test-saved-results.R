test_that("committed metrics support the headline result", {
  path <- testthat::test_path("..", "..", "results", "model_metrics.csv")
  skip_if_not(file.exists(path), "committed result snapshot not present")
  metrics <- data.table::fread(path)
  expect_equal(nrow(metrics), 28L)
  expect_equal(data.table::uniqueN(metrics$model), 7L)
  expect_equal(sort(unique(metrics$horizon)), c(1L, 5L, 10L, 22L))
  expect_equal(sum(metrics$forecasts), 127218L)
  best <- metrics[, .SD[which.min(QLIKE)], by = horizon]
  expected <- c(`1` = "Elastic_Net", `5` = "Elastic_Net",
    `10` = "HAR_VIX", `22` = "HAR_VIX")
  expect_equal(best$model, unname(expected[as.character(best$horizon)]))
  headline_path <- testthat::test_path("..", "..", "results",
    "headline_metrics.json")
  headline <- jsonlite::read_json(headline_path, simplifyVector = TRUE)
  expect_identical(headline$method_revision,
    "glmnet_lambda_mapping_corrected_2026-09")
  expect_equal(headline$failed_forecast_rows, 0L)
})
