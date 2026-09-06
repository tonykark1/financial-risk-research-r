render_macro_reports <- function(model_suite, evaluation, config, importance = NULL,
                                 vintage_coverage = NULL) {
  dir.create("figures/macro_vol", recursive = TRUE, showWarnings = FALSE)
  best <- evaluation$metrics[order(horizon, QLIKE), .SD[1L], by = horizon]
  p <- ggplot2::ggplot(evaluation$metrics,
    ggplot2::aes(x = reorder(model, QLIKE), y = QLIKE, fill = factor(horizon))) +
    ggplot2::geom_col(position = "dodge") + ggplot2::coord_flip() +
    ggplot2::labs(x = NULL, fill = "Horizon", title = "Out-of-sample QLIKE by model") +
    ggplot2::theme_minimal(base_size = 11)
  figure <- "figures/macro_vol/model_qlike.png"
  ggplot2::ggsave(figure, p, width = 9, height = 5.5, dpi = 150)
  summary <- paste0(
    "The experiment uses only true-vintage macro observations in historical forecasts. ",
    "All scaling, imputation, tuning, and fitting occur inside each expanding training window. ",
    "The strongest QLIKE model is reported separately for each horizon."
  )
  main <- write_quarto_report("Real-Time Macro / Volatility Forecasting", summary,
    list("True-vintage coverage manifest" = vintage_coverage,
      "Best model by horizon" = best, "All out-of-sample metrics" = evaluation$metrics,
      "Diebold-Mariano tests versus HAR" = evaluation$dm_tests),
    "reports/macro_vol/macro_volatility_forecasting.qmd", config, figures = figure
  )
  comparison_sections <- list("Model ranking" = evaluation$metrics, "DM tests" = evaluation$dm_tests)
  if (!is.null(importance)) comparison_sections[["Feature importance and stability"]] <- importance
  comparison <- write_quarto_report("Macro Model Comparison", summary,
    comparison_sections,
    "reports/macro_vol/model_comparison.qmd", config
  )
  regimes <- write_quarto_report("Macro Forecast Regime Analysis",
    "Regime thresholds are fixed from the initial training window or set by economic convention; they are not optimized on forecast performance.",
    list("Regime QLIKE" = evaluation$regime_metrics),
    "reports/macro_vol/regime_analysis.qmd", config
  )
  c(main, comparison, regimes, figure)
}
