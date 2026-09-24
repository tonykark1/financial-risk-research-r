test_that("glmnet tuning refits the lambda that actually won validation", {
  n <- 140L
  train <- data.table::data.table(
    x1 = seq(-2, 2, length.out = n),
    x2 = sin(seq(0, 4 * pi, length.out = n))
  )
  train[, target := 5 + 3 * x1 - 1.5 * x2]

  predictors <- c("x1", "x2")
  prep <- training_preprocessor(train, predictors)
  x <- apply_preprocessor(train, predictors, prep)
  y <- train$target
  split <- chronological_validation_indices(nrow(train))
  lambda_grid <- exp(seq(log(1e-5), log(1), length.out = 30L))

  for (model in c("Ridge", "Elastic_Net")) {
    alpha <- if (model == "Ridge") 0 else 0.5
    validation_fit <- glmnet::glmnet(
      x[split$train, , drop = FALSE], y[split$train],
      alpha = alpha, lambda = lambda_grid, standardize = FALSE
    )
    validation_predictions <- predict(
      validation_fit,
      x[split$validation, , drop = FALSE]
    )
    losses <- colMeans(
      (validation_predictions - y[split$validation])^2,
      na.rm = TRUE
    )
    best_index <- which.min(losses)
    expected_lambda <- validation_fit$lambda[[best_index]]

    fitted <- fit_forecast_model(
      train = train,
      target = "target",
      predictors = predictors,
      model = model,
      seed = 42L
    )

    expect_equal(fitted$hyperparameters$lambda, expected_lambda, tolerance = 1e-12)
    expect_false(isTRUE(all.equal(
      expected_lambda,
      lambda_grid[[best_index]],
      tolerance = 1e-12
    )))
  }
})
