render_bank_reports <- function(features, quality, models, stress, config,
                                importance = NULL) {
  dir.create("figures/bank_risk", recursive = TRUE, showWarnings = FALSE)
  latest <- features[quarter == max(quarter, na.rm = TRUE)][order(-overall_risk_score)]
  p <- ggplot2::ggplot(latest[is.finite(overall_risk_score)],
    ggplot2::aes(x = overall_risk_score)) + ggplot2::geom_histogram(bins = 25, fill = "#1f618d") +
    ggplot2::theme_minimal() + ggplot2::labs(
      title = "Latest capital and profitability monitoring-score distribution",
      x = "Monitoring score", y = "Banks")
  figure <- "figures/bank_risk/risk_score_distribution.png"
  ggplot2::ggsave(figure, p, width = 8, height = 4.5, dpi = 150)
  summary <- paste0(
    "The bank panel contains **", data.table::uniqueN(features$bank_id), " banks** across **",
    data.table::uniqueN(features$quarter), " reporting periods**. Capital and profitability ",
    "dimensions are scored where supported. This is a **capital and profitability monitor, ",
    "not a comprehensive bank-risk model**. Credit, bank-equity market, and country-macro ",
    "dimensions remain explicitly unavailable rather than imputed from unsuitable aggregates. ",
    "Availability is conservative pseudo-PIT because exact EBA publication timestamps are absent."
  )

  # Keep the flagship report legible in both HTML and the Letter-sized PDF.
  # Complete rankings remain available in the Parquet outputs; the report shows
  # the decision-relevant leading rows and deliberately short column labels.
  repair_label <- function(x) {
    repaired <- suppressWarnings(iconv(x, from = "windows-1252", to = "UTF-8"))
    bad <- grepl("Ã|â", x)
    x[bad & !is.na(repaired)] <- repaired[bad & !is.na(repaired)]
    x
  }
  display_bank <- function(name, id) {
    name <- repair_label(name)
    missing <- is.na(name) | !nzchar(trimws(name))
    name[missing] <- paste0("Unmapped LEI ", substr(id[missing], 1L, 12L), "...")
    name
  }
  ranking_table <- latest[, .(
    Bank = display_bank(bank_name, bank_id), Country = country,
    `CET1 (%)` = round(100 * CET1, 2),
    `Leverage (%)` = round(100 * leverage_ratio, 2),
    `RWA density (%)` = round(100 * RWA_density, 2),
    `Monitoring score` = round(overall_risk_score, 3)
  )][1:min(.N, 15)]
  stress_table <- stress$results[order(scenario, vulnerability_rank), .(
    Bank = display_bank(bank_name, bank_id), Scenario = scenario,
    `Change (pp)` = round(100 * estimated_cet1_change, 2),
    `Stressed (%)` = round(100 * stressed_CET1, 2),
    Rank = vulnerability_rank
  )][1:min(.N, 15)]
  coverage <- data.table::data.table(
    Dimension = c("Capital", "Profitability", "Credit", "Bank equity market", "Country macro"),
    Supported = c(TRUE, TRUE, FALSE, FALSE, FALSE),
    Treatment = c("Scored", "Scored where ROA is available", rep("Explicitly unavailable", 3))
  )
  timing <- data.table::data.table(
    field = c("Status", "Availability rule", "Interpretation"),
    value = c("Conservative pseudo-PIT", "Quarter end + 120 calendar days",
      "Prevents early use but is not an exact EBA publication calendar")
  )
  main <- write_quarto_report("European Bank Capital & Profitability Monitor", summary,
    list("Latest transparent ranking" = ranking_table,
      "Descriptive scenario ranking" = stress_table,
      "Dimension coverage" = coverage,
      "Information-timing status" = timing),
    "reports/bank_risk/bank_risk_monitor.qmd", config, formats = c("html", "typst"), figures = figure
  )
  methodology <- write_quarto_report("Bank Monitoring Methodology",
    "Primary monitoring scores use within-period robust median/MAD scaling and equal weights across available dimensions. They are not probabilities of default or comprehensive risk estimates. Economic weights are retained as a sensitivity check. Scenario mappings are descriptive historical sensitivities, not causal stress-test losses. Observation availability is conservative pseudo-PIT because exact EBA publication timestamps are absent.",
    list("Data quality checks" = quality$summary), "reports/bank_risk/methodology.qmd", config
  )
  validation_sections <- list("Out-of-sample model metrics" = models$metrics)
  if (!is.null(importance)) validation_sections[["Feature importance and stability"]] <- importance
  validation <- write_quarto_report("Bank Model Validation",
    "All evaluation is chronological. Targets are forward changes and training rows are admitted only after their target quarter precedes the forecast quarter. Every fitted model has negative out-of-sample R-squared versus the zero-change persistence benchmark; the system is therefore presented as monitoring and sensitivity analysis, not predictive success.",
    validation_sections,
    "reports/bank_risk/model_validation.qmd", config
  )
  quality_report <- write_quarto_report("Bank Data Quality Report",
    "Anomalies are retained and flagged. Implausible ratios are excluded only from model-ready copies while their raw values remain in the panel.",
    list("Quality checks" = quality$summary), "reports/bank_risk/data_quality_report.qmd", config
  )
  c(main, methodology, validation, quality_report, figure)
}
