walk_forward_splits <- function(dates, target_available_dates = dates,
                                initial_window, retrain_frequency = 1L) {
  dates <- as_date_utc(dates)
  available <- as_date_utc(target_available_dates)
  order_index <- order(dates)
  dates <- dates[order_index]
  available <- available[order_index]
  if (length(dates) <= initial_window) stop("Initial window leaves no forecasts")
  test_indices <- seq.int(initial_window + 1L, length(dates))
  lapply(seq_along(test_indices), function(j) {
    test_index <- test_indices[[j]]
    forecast_date <- dates[[test_index]]
    train_index <- which(dates < forecast_date & available < forecast_date)
    list(
      train = order_index[train_index],
      test = order_index[test_index],
      training_start = min(dates[train_index]),
      training_end = max(dates[train_index]),
      forecast_date = forecast_date,
      retrain = (j - 1L) %% retrain_frequency == 0L
    )
  })
}

training_preprocessor <- function(train, predictors) {
  medians <- vapply(train[, predictors, with = FALSE], stats::median,
    numeric(1), na.rm = TRUE
  )
  medians[!is.finite(medians)] <- 0
  scales <- vapply(train[, predictors, with = FALSE], stats::sd,
    numeric(1), na.rm = TRUE
  )
  scales[!is.finite(scales) | scales <= .Machine$double.eps] <- 1
  list(medians = medians, scales = scales)
}

apply_preprocessor <- function(data, predictors, prep, scale = TRUE) {
  x <- as.matrix(data[, predictors, with = FALSE])
  storage.mode(x) <- "double"
  for (j in seq_along(predictors)) {
    x[!is.finite(x[, j]), j] <- prep$medians[[j]]
    if (scale) x[, j] <- (x[, j] - prep$medians[[j]]) / prep$scales[[j]]
  }
  x
}

chronological_validation_indices <- function(n, fraction = 0.2, minimum = 50L) {
  validation_n <- max(minimum, floor(n * fraction))
  validation_n <- min(validation_n, max(1L, n - minimum))
  list(train = seq_len(n - validation_n), validation = seq.int(n - validation_n + 1L, n))
}

fit_forecast_model <- function(train, target, predictors, model, tuning = TRUE, seed = 1L) {
  train <- data.table::as.data.table(train)
  train <- train[is.finite(get(target))]
  if (nrow(train) < max(60L, length(predictors) * 5L)) stop("Insufficient training observations")
  prep <- training_preprocessor(train, predictors)
  x <- apply_preprocessor(train, predictors, prep)
  y <- train[[target]]
  split <- chronological_validation_indices(nrow(train))
  set.seed(seed)
  if (model %in% c("HAR", "HAR_VIX", "HAR_Rates", "OLS")) {
    fit <- stats::lm.fit(cbind(`(Intercept)` = 1, x), y)
    return(list(model = model, fit = fit, prep = prep, predictors = predictors,
      hyperparameters = list(), scale = TRUE
    ))
  }
  if (model %in% c("Ridge", "Elastic_Net")) {
    alpha <- if (model == "Ridge") 0 else 0.5
    lambda_grid <- exp(seq(log(1e-5), log(1), length.out = 30L))
    base_fit <- glmnet::glmnet(x[split$train, , drop = FALSE], y[split$train],
      alpha = alpha, lambda = lambda_grid, standardize = FALSE
    )
    validation_predictions <- predict(base_fit, x[split$validation, , drop = FALSE])
    losses <- colMeans((validation_predictions - y[split$validation])^2, na.rm = TRUE)
    lambda <- lambda_grid[[which.min(losses)]]
    fit <- glmnet::glmnet(x, y, alpha = alpha, lambda = lambda, standardize = FALSE)
    return(list(model = model, fit = fit, prep = prep, predictors = predictors,
      hyperparameters = list(alpha = alpha, lambda = lambda), scale = TRUE
    ))
  }
  if (model == "Random_Forest") {
    candidates <- unique(pmax(1L, pmin(ncol(x), c(2L, floor(sqrt(ncol(x))), floor(ncol(x) / 2L)))))
    scores <- vapply(candidates, function(mtry) {
      fit <- ranger::ranger(x = x[split$train, , drop = FALSE], y = y[split$train],
        num.trees = 200L, mtry = mtry, min.node.size = 10L, seed = seed,
        num.threads = 1L
      )
      pred <- predict(fit, x[split$validation, , drop = FALSE])$predictions
      mean((pred - y[split$validation])^2)
    }, numeric(1))
    mtry <- candidates[[which.min(scores)]]
    fit <- ranger::ranger(x = x, y = y, num.trees = 400L, mtry = mtry,
      min.node.size = 10L, seed = seed, importance = "permutation", num.threads = 1L
    )
    return(list(model = model, fit = fit, prep = prep, predictors = predictors,
      hyperparameters = list(mtry = mtry, min_node_size = 10L, trees = 400L), scale = TRUE
    ))
  }
  if (model == "XGBoost") {
    grid <- data.table::CJ(max_depth = c(2L, 3L), eta = c(0.03, 0.08))
    scores <- vapply(seq_len(nrow(grid)), function(i) {
      fit <- xgboost::xgboost(
        x = x[split$train, , drop = FALSE], y = y[split$train],
        objective = "reg:squarederror", nrounds = 120L,
        max_depth = grid$max_depth[[i]], learning_rate = grid$eta[[i]], subsample = 0.8,
        colsample_bytree = 0.8, nthreads = 1L, verbosity = 0
      )
      pred <- predict(fit, x[split$validation, , drop = FALSE])
      mean((pred - y[split$validation])^2)
    }, numeric(1))
    best <- grid[which.min(scores)]
    fit <- xgboost::xgboost(x = x, y = y, objective = "reg:squarederror",
      nrounds = 160L, max_depth = best$max_depth, learning_rate = best$eta,
      subsample = 0.8, colsample_bytree = 0.8, nthreads = 1L, verbosity = 0
    )
    return(list(model = model, fit = fit, prep = prep, predictors = predictors,
      hyperparameters = as.list(best), scale = TRUE
    ))
  }
  stop("Unknown model: ", model)
}

predict_forecast_model <- function(object, new_data) {
  dt <- data.table::as.data.table(new_data)
  x <- apply_preprocessor(dt, object$predictors, object$prep, scale = object$scale)
  if (object$model %in% c("HAR", "HAR_VIX", "HAR_Rates", "OLS")) {
    coefficients <- object$fit$coefficients
    coefficients[!is.finite(coefficients)] <- 0
    return(as.numeric(cbind(1, x) %*% coefficients))
  }
  if (object$model %in% c("Ridge", "Elastic_Net")) return(as.numeric(predict(object$fit, x)))
  if (object$model == "Random_Forest") return(as.numeric(predict(object$fit, x)$predictions))
  if (object$model == "XGBoost") return(as.numeric(predict(object$fit, x)))
  stop("Unsupported fitted model")
}

run_walk_forward <- function(data, target, predictors, model, horizon,
                             initial_window, retrain_frequency = 22L,
                             tuning = TRUE, date_col = "date",
                             target_available_col = "target_available_date",
                             seed = 20260813L) {
  dt <- data.table::as.data.table(data.table::copy(data))
  data.table::setorderv(dt, date_col)
  splits <- walk_forward_splits(dt[[date_col]], dt[[target_available_col]],
    initial_window = initial_window, retrain_frequency = retrain_frequency
  )
  retrain_flags <- unlist(lapply(splits, function(split) isTRUE(split$retrain)),
    use.names = FALSE
  )
  origins <- which(retrain_flags)
  results <- vector("list", length(origins))
  for (block_id in seq_along(origins)) {
    origin <- origins[[block_id]]
    block_end <- if (block_id < length(origins)) origins[[block_id + 1L]] - 1L else length(splits)
    block <- seq.int(origin, block_end)
    split <- splits[[origin]]
    train <- dt[split$train]
    test_indices <- as.integer(unlist(lapply(splits[block], function(item) item$test),
      use.names = FALSE
    ))
    test <- dt[test_indices]
    fitted <- tryCatch(fit_forecast_model(train, target, predictors, model,
      tuning = tuning, seed = seed + origin
    ), error = function(e) e)
    if (inherits(fitted, "error")) {
      prediction <- rep(NA_real_, nrow(test))
      parameters <- jsonlite::toJSON(list(error = conditionMessage(fitted)), auto_unbox = TRUE)
    } else {
      prediction <- predict_forecast_model(fitted, test)
      parameters <- jsonlite::toJSON(fitted$hyperparameters, auto_unbox = TRUE)
    }
    results[[block_id]] <- data.table::data.table(
      model = model, horizon = horizon,
      training_start = split$training_start, training_end = split$training_end,
      forecast_date = test[[date_col]],
      target_available_date = test[[target_available_col]],
      actual = test[[target]], prediction = prediction,
      hyperparameters = parameters,
      n_train = nrow(train)
    )
  }
  data.table::rbindlist(results)
}
