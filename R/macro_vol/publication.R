write_public_macro_results <- function(evaluation, vintage_coverage, predictions, config) {
  output_dir <- project_path("results", root = config$project_root)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  metrics <- data.table::copy(evaluation$metrics)[order(horizon, rank_QLIKE, model)]
  dm <- data.table::copy(evaluation$dm_tests)[order(horizon, model)]
  regimes <- data.table::copy(evaluation$regime_metrics)[order(horizon, regime, model)]
  coverage <- data.table::copy(vintage_coverage)[order(series_id)]
  predictions <- data.table::as.data.table(data.table::copy(predictions))
  forecast_dates <- as.Date(predictions$forecast_date)
  failed_forecasts <- sum(!is.finite(predictions$prediction))
  paths <- file.path(output_dir, c(
    "model_metrics.csv", "dm_tests.csv", "regime_metrics.csv", "vintage_coverage.csv"
  ))
  data.table::fwrite(metrics, paths[[1L]])
  data.table::fwrite(dm, paths[[2L]])
  data.table::fwrite(regimes, paths[[3L]])
  data.table::fwrite(coverage, paths[[4L]])

  best <- metrics[, .SD[which.min(QLIKE)], by = horizon]
  headline <- list(
    generated_from = "executed walk-forward prediction outputs",
    method_revision = "glmnet_lambda_mapping_corrected_2026-09",
    model_forecasts = as.integer(sum(metrics$forecasts)),
    failed_forecast_rows = as.integer(failed_forecasts),
    model_horizon_combinations = nrow(metrics),
    date_horizon_evaluations = as.integer(sum(metrics[model == "HAR"]$forecasts)),
    maximum_unique_forecast_dates = as.integer(max(metrics$forecasts)),
    unique_forecast_dates = as.integer(data.table::uniqueN(forecast_dates)),
    first_forecast_date = as.character(min(forecast_dates, na.rm = TRUE)),
    last_forecast_date = as.character(max(forecast_dates, na.rm = TRUE)),
    models = data.table::uniqueN(metrics$model),
    horizons_days = sort(unique(metrics$horizon)),
    best_qlike_by_horizon = lapply(seq_len(nrow(best)), function(i) {
      list(
        horizon_days = as.integer(best$horizon[[i]]),
        model = best$model[[i]],
        qlike = unname(best$QLIKE[[i]]),
        forecasts = as.integer(best$forecasts[[i]])
      )
    })
  )
  headline_path <- file.path(output_dir, "headline_metrics.json")
  jsonlite::write_json(headline, headline_path, auto_unbox = TRUE, pretty = TRUE,
    digits = 10)
  normalizePath(c(paths, headline_path), winslash = "/", mustWork = TRUE)
}

write_macro_report <- function(evaluation, vintage_coverage, predictions, config,
                               path = "report/analysis.md") {
  output <- project_path(path, root = config$project_root)
  dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
  metrics <- data.table::copy(evaluation$metrics)[order(horizon, rank_QLIKE, model)]
  predictions <- data.table::as.data.table(data.table::copy(predictions))
  forecast_dates <- as.Date(predictions$forecast_date)
  failed_forecasts <- sum(!is.finite(predictions$prediction))
  best <- metrics[, .SD[which.min(QLIKE)], by = horizon]
  best_table <- best[, .(
    `Horizon` = paste0(horizon, " days"),
    `Lowest-QLIKE model` = model,
    `Forecast records` = forecasts,
    QLIKE = round(QLIKE, 6),
    RMSE = round(RMSE, 7)
  )]
  har_vix_dm <- evaluation$dm_tests[model == "HAR_VIX"][order(horizon), .(
    `Horizon` = paste0(horizon, " days"),
    `HAC DM statistic` = round(statistic, 3),
    `Nominal p-value` = format.pval(p_value, digits = 4, eps = 1e-7)
  )]
  coverage_table <- data.table::copy(vintage_coverage)[, .(
    Series = series_id,
    `Visible release dates` = distinct_visible_releases,
    `Median release lag (days)` = median_release_lag_days,
    `Pipeline admits revised history` = revised_history_admitted
  )]
  model_count <- data.table::uniqueN(metrics$model)
  model_forecasts <- sum(metrics$forecasts)
  date_horizon <- sum(metrics[model == "HAR"]$forecasts)

  text <- c(
    "# Point-in-Time Volatility Forecasting",
    "",
    "## Research question",
    "",
    "**Does information genuinely available at forecast time improve equity-index volatility forecasts beyond a parsimonious HAR baseline?**",
    "",
    "The corrected experiment has a split result: **Elastic Net had the lowest sample-average out-of-sample QLIKE at 1 and 5 days, while HAR plus VIX led at 10 and 22 days.** Neither tested tree ensemble led at any horizon under the implemented grids, validation objective, and retraining schedules. These are sample- and metric-specific rankings, not a general theorem that nonlinear models cannot help.",
    "",
    "![Benchmark-relative forecast loss](../figures/benchmark-relative-qlike.png)",
    "",
    "## Data and forecast target",
    "",
    "The source panel starts from S&P 500 close-to-close daily returns and daily VIX observations in a read-only local data lake. The target is the sum of subsequent squared daily returns over 1, 5, 10, or 22 trading days. It is a **daily close-to-close variance proxy**, not an intraday realized-volatility measure.",
    "",
    sprintf("Release-dated macro candidates include the federal funds rate, 2- and 10-year Treasury yields, the high-yield spread, unemployment, CPI, industrial production, and real GDP. A coverage audit also retains VIXCLS and T10Y2Y, but the model uses market VIX and reconstructs the curve slope from DGS10 minus DGS2. Forecast dates run from %s through %s. The analysis imposes an after-close convention for same-day HAR and market-VIX inputs; the source records do not contain intraday availability timestamps, and each target uses only subsequent returns.",
      as.character(min(forecast_dates, na.rm = TRUE)), as.character(max(forecast_dates, na.rm = TRUE))),
    "",
    "## Point-in-time design",
    "",
    "- Each macro observation carries both an observation date and an availability date.",
    "- As-of joins reject releases that were not yet visible on the forecast date.",
    "- A forward target becomes eligible for training only after its full horizon has elapsed.",
    "- Forecasting begins after a 756-row history; horizon-specific target gating leaves slightly fewer eligible training observations.",
    "- Imputation and scaling use the outer training window; the held-out test observations never enter preprocessing or fitting.",
    "- Linear and regularised models retrain every 22 trading days; tree models retrain every 66 days.",
    "- Overlapping-horizon Diebold-Mariano comparisons use Newey-West/HAC covariance with horizon-dependent lags.",
    sprintf("- Fitting errors are retained as missing row-level predictions; this execution recorded %s failed forecast rows. Underperforming specifications remain in the committed metrics.", failed_forecasts),
    "",
    "One methodological caveat matters: preprocessing is fitted on the full outer training window before the final 20% of that window is used for hyperparameter selection. There is no test-set leakage, but preprocessing is not strictly nested with respect to the tuning holdout.",
    "",
    "## Models",
    "",
    "1. **HAR:** log daily, weekly, and monthly volatility components.",
    "2. **HAR + VIX:** HAR plus log market VIX.",
    "3. **HAR + rates:** HAR plus the policy rate, 10-year yield, and curve slope.",
    "4. **Ridge:** the full candidate set, fixed alpha 0, with 30 candidate penalties.",
    "5. **Elastic Net:** the full set, fixed alpha 0.5, with 30 candidate penalties.",
    "6. **Random Forest:** a small predefined search over `mtry`; 400 trees in the final fit.",
    "7. **XGBoost:** four depth/learning-rate combinations with fixed sampling settings.",
    "",
    "Hyperparameters are selected on a chronological validation tail using log-variance mean squared error. QLIKE is the primary final ranking metric, so the tree-model result should be read as a comparison of the implemented protocols rather than an exhaustive optimisation of QLIKE.",
    "",
    "**Method revision (September 2026):** an audit found that `glmnet` reordered the supplied penalty path. Ridge and Elastic Net now select the validation winner from `base_fit$lambda`, and every published result artifact in this release was regenerated after that correction.",
    "",
    "## Evaluation scale",
    "",
    sprintf("The saved predictions contain **%s model forecasts** across **%s model-horizon combinations**. This count is %s models multiplied by %s date-horizon evaluations. The evaluations reuse the same forecast origins across models and horizons, and multi-day targets overlap, so they are not %s independent market events. The largest horizon-specific panel contains %s unique forecast dates.",
      format(model_forecasts, big.mark = ","), nrow(metrics), model_count,
      format(date_horizon, big.mark = ","), format(model_forecasts, big.mark = ","),
      format(max(metrics$forecasts), big.mark = ",")),
    "",
    "## Main results",
    "",
    write_markdown_table(best_table),
    "",
    "Lower QLIKE is better. The implementation averages `log(f) + y/f`, where `f` is forecast variance and `y` is the variance proxy. It omits an actual-only normalisation, which does not affect paired rankings; compare models within a horizon rather than raw QLIKE levels across horizons.",
    "",
    "![QLIKE across models and horizons](../figures/macro_gallery/01-macro-qlike-by-horizon.png)",
    "Elastic Net leads on average QLIKE at 1 and 5 days. At 10 days, HAR plus VIX and Elastic Net are nearly tied; no direct pairwise significance claim is made between them.",
    "",
    "",
    "HAR plus VIX also has a lower average QLIKE than HAR at every horizon. Negative HAC Diebold-Mariano statistics favour HAR plus VIX. The comparisons are nominally significant at 5%, but the 22-day result is borderline and the table does not adjust for the 24 reported model-horizon comparisons against HAR.",
    "",
    write_markdown_table(har_vix_dm),
    "",
    "![HAC Diebold-Mariano comparison](../figures/macro_gallery/09-macro-dm-significance.png)",
    "",
    "## What the negative complexity result means",
    "",
    "On full-sample average QLIKE, the implemented Random Forest and XGBoost specifications ranked below HAR plus VIX at every horizon. The result is not uniform across every economic-regime cell, and it does **not** establish that all nonlinear models, wider searches, alternative retraining schedules, or QLIKE-targeted tuning would fail.",
    "",
    "## Vintage coverage",
    "",
    write_markdown_table(coverage_table),
    "",
    "The final column records the pipeline policy applied to the availability-dated input, not an independent reconstruction of every provider's revision history.",
    "",
    "![Vintage coverage](../figures/macro_gallery/10-macro-vintage-coverage.png)",
    "",
    "## Limitations",
    "",
    "- The target is based on daily close-to-close returns, not intraday realized volatility.",
    sprintf("- The evidence covers one equity index and forecast dates from %s through %s; other indices and periods are untested.", as.character(min(forecast_dates, na.rm = TRUE)), as.character(max(forecast_dates, na.rm = TRUE))),
    "- Market history is retrieval-time data; availability-date controls apply to the macro-release panel.",
    "- The tuning grids are deliberately small, selection uses log-MSE rather than QLIKE, and tree models retrain less often.",
    "- Models are fitted to log variance and exponentiated for level metrics without a separate smearing correction.",
    "- Nominal DM p-values are not adjusted for multiple comparisons.",
    "- The analysis evaluates forecast loss, not positions, turnover, transaction costs, or trading profitability.",
    "- A full numerical rebuild requires the private source lake. The public demo verifies mechanics, not the full headline result.",
    "",
    "## Reproduction",
    "",
    "```r",
    "renv::restore()",
    "targets::tar_make()",
    "testthat::test_dir(\"tests/testthat\")",
    "```",
    "",
    "Before the full pipeline, set `FINANCIAL_RESEARCH_UPSTREAM_ROOT` to the supplied source-lake directory. For a portable check that needs no private data, run:",
    "",
    "```text",
    "Rscript scripts/run_demo.R",
    "```",
    "",
    "The committed result snapshots are in [`results/`](../results/)."
  )
  atomic_write_lines(text, output)
}
