build_case_study_assets <- function(macro_evaluation, bank_features, bank_stress,
                                    accounting_quality, company_kpis, config) {
  output_dir <- project_path("figures/case-study", root = config$project_root)
  metrics_path <- project_path("reports/case_study_metrics.json", root = config$project_root)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  palette <- gallery_palette()

  macro <- data.table::copy(macro_evaluation$metrics)
  benchmark <- macro[model == "HAR", .(horizon, benchmark_qlike = QLIKE)]
  macro <- merge(macro, benchmark, by = "horizon")
  macro[, relative_qlike := QLIKE - benchmark_qlike]
  macro[, horizon_label := factor(paste0(horizon, "d"),
    levels = paste0(sort(unique(horizon)), "d"))]
  macro_plot <- ggplot2::ggplot(macro, ggplot2::aes(horizon_label, relative_qlike,
      colour = model, group = model)) +
    ggplot2::geom_hline(yintercept = 0, colour = "#708090", linewidth = .5) +
    ggplot2::geom_line(linewidth = .75) + ggplot2::geom_point(size = 2.2) +
    ggplot2::scale_colour_manual(values = rep(palette,
      length.out = data.table::uniqueN(macro$model))) +
    ggplot2::labs(
      title = "Forecast loss relative to HAR",
      subtitle = "Negative values beat the HAR benchmark; positive values underperform it.",
      x = "Forecast horizon", y = "QLIKE difference versus HAR", colour = "Model"
    ) + gallery_theme()
  relative_path <- save_gallery_plot(macro_plot, "01-benchmark-relative-qlike",
    output_dir, width = 9.6, height = 5.6)

  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  quality <- data.table::as.data.table(DBI::dbGetQuery(con, sprintf(paste(
    "SELECT count(*) AS eligible_records,",
    "avg(CAST(identity_flag AS INTEGER)) AS identity_break,",
    "avg(CAST(malformed_period_flag AS INTEGER)) AS malformed_period,",
    "avg(CAST(malformed_available_flag AS INTEGER)) AS malformed_available,",
    "avg(CAST(future_period_flag AS INTEGER)) AS future_period,",
    "avg(CAST(period_after_filing_flag AS INTEGER)) AS period_after_filing,",
    "avg(CAST(duplicate_vintage_flag AS INTEGER)) AS duplicate_vintage,",
    "avg(CAST(restatement_change_pct > 0.1 AS INTEGER)) AS large_restatement",
    "FROM read_parquet(%s)"
  ), sql_path(accounting_quality$flags_path))))
  eligible_records <- quality$eligible_records[[1L]]
  quality[, eligible_records := NULL]
  quality <- data.table::melt(quality, measure.vars = names(quality),
    variable.name = "flag", value.name = "rate")
  quality[, label := factor(gsub("_", " ", flag),
    levels = gsub("_", " ", flag)[order(rate)])]
  quality_plot <- ggplot2::ggplot(quality, ggplot2::aes(100 * rate, label)) +
    ggplot2::geom_col(fill = palette[[4L]], width = .7) +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.2f%%", 100 * rate)),
      hjust = -0.08, size = 3.4) +
    ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0, .16))) +
    ggplot2::labs(
      title = "Accounting-quality flag rates",
      subtitle = "Rates use all eligible records, making checks comparable despite different volumes.",
      x = "Flagged records (%)", y = NULL
    ) + gallery_theme()
  quality_path <- save_gallery_plot(quality_plot, "08-accounting-quality-rates",
    output_dir, width = 9.6, height = 5.8)

  latest <- bank_features[quarter == max(quarter, na.rm = TRUE)]
  stress <- bank_stress$results[is.finite(stressed_CET1)]
  kpi_summary <- data.table::as.data.table(DBI::dbGetQuery(con, sprintf(paste(
    "SELECT count(*) AS records, count(DISTINCT CIK) AS companies,",
    "min(TRY_CAST(period_end AS DATE)) AS first_period,",
    "max(TRY_CAST(period_end AS DATE)) AS last_period FROM read_parquet(%s)"
  ), sql_path(company_kpis$kpis_path))))
  best <- macro[model != "HAR"][order(relative_qlike), .SD[1L], by = horizon]
  metrics <- list(
    generated_on = format(Sys.Date(), "%Y-%m-%d"),
    macro_forecasts = as.integer(sum(macro$forecasts)),
    macro_best_models = lapply(seq_len(nrow(best)), function(i) list(
      horizon_days = as.integer(best$horizon[[i]]), model = best$model[[i]],
      qlike_difference_vs_har = unname(best$relative_qlike[[i]])
    )),
    bank_latest_quarter = format(max(latest$quarter, na.rm = TRUE), "%Y-%m-%d"),
    bank_count = data.table::uniqueN(latest$bank_id),
    bank_median_cet1_pct = 100 * stats::median(latest$CET1_model, na.rm = TRUE),
    stress_scenarios = data.table::uniqueN(stress$scenario),
    sec_kpi_records = as.integer(kpi_summary$records[[1L]]),
    sec_companies = as.integer(kpi_summary$companies[[1L]]),
    sec_first_period = as.character(kpi_summary$first_period[[1L]]),
    sec_last_period = as.character(kpi_summary$last_period[[1L]]),
    accounting_records_checked = as.integer(eligible_records),
    accounting_flag_rates = stats::setNames(as.list(quality$rate), as.character(quality$flag))
  )
  jsonlite::write_json(metrics, metrics_path, pretty = TRUE, auto_unbox = TRUE,
    digits = 8, na = "null")
  normalizePath(c(relative_path, quality_path, metrics_path), winslash = "/",
    mustWork = TRUE)
}
