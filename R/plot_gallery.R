gallery_palette <- function() {
  c("#17365D", "#2E75B6", "#00A6A6", "#F2A900", "#C43C39", "#6F4E7C", "#708090")
}

gallery_theme <- function(base_size = 11) {
  research_theme(base_size) + ggplot2::theme(
    plot.title = ggplot2::element_text(face = "bold", colour = "#17365D", size = base_size + 3),
    plot.subtitle = ggplot2::element_text(colour = "#4C5B6B", margin = ggplot2::margin(b = 10)),
    axis.title = ggplot2::element_text(face = "bold"),
    panel.grid.major = ggplot2::element_line(colour = "#E4E9EF", linewidth = 0.3),
    strip.text = ggplot2::element_text(face = "bold"),
    strip.background = ggplot2::element_rect(fill = "#EDF2F7", colour = NA)
  )
}

save_gallery_plot <- function(plot, slug, directory, width = 9, height = 5.4) {
  path <- file.path(directory, paste0(slug, ".png"))
  ggplot2::ggsave(path, plot, width = width, height = height, dpi = 160, bg = "white")
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

gallery_manifest <- function() {
  data.table::data.table(
    number = seq_len(30L),
    domain = rep(c("Macro volatility", "Bank risk", "Company fundamentals"), each = 10L),
    slug = c(
      "01-macro-qlike-by-horizon", "02-macro-rmse-by-horizon", "03-macro-model-rank-heatmap",
      "04-macro-actual-vs-forecast", "05-macro-forecast-calibration", "06-macro-residual-distribution",
      "07-macro-cumulative-loss-difference", "08-macro-regime-heatmap", "09-macro-dm-significance",
      "10-macro-vintage-coverage", "11-bank-cet1-distribution", "12-bank-leverage-distribution",
      "13-bank-risk-dimensions", "14-bank-capital-profitability", "15-bank-cet1-trend",
      "16-bank-roa-trend", "17-bank-highest-risk", "18-bank-model-rmse", "19-bank-oos-r2",
      "20-bank-stress-scenarios", "21-fundamentals-kpi-records", "22-fundamentals-company-coverage",
      "23-fundamentals-gross-margin", "24-fundamentals-operating-margin",
      "25-fundamentals-revenue-growth", "26-fundamentals-leverage", "27-fundamentals-anomaly-flags",
      "28-fundamentals-accounting-flags", "29-fundamentals-coverage-over-time",
      "30-fundamentals-kpi-trends"
    ),
    title = c(
      "Forecast QLIKE by horizon", "Forecast RMSE by horizon", "Model rank consistency",
      "Actual versus 22-day forecast", "22-day forecast calibration", "22-day log-error distribution",
      "Cumulative loss versus HAR", "Performance across stress regimes", "Diebold-Mariano significance",
      "True-vintage macro coverage", "Latest CET1 distribution", "Latest leverage-ratio distribution",
      "Capital and profitability risk", "Capital versus profitability", "CET1 median and interquartile range",
      "ROA median and interquartile range", "Banks with the highest monitoring scores", "Bank-model RMSE",
      "Bank-model out-of-sample R-squared", "CET1 under macro scenarios", "KPI record coverage",
      "Company coverage by KPI", "Gross-margin distribution", "Operating-margin distribution",
      "Revenue-growth distribution", "Debt-to-equity distribution", "Fundamental anomaly flags",
      "Accounting-quality flags", "KPI coverage over time", "Annual KPI medians over time"
    ),
    caption = c(
      "Compares variance-forecast loss across models and horizons.",
      "Shows level-error trade-offs that QLIKE alone can conceal.",
      "Tests whether model leadership is stable across forecast horizons.",
      "Places the strongest interpretable specification against realized variance through time.",
      "Checks bias, dispersion, and extreme-event calibration on log scales.",
      "Shows whether forecast errors are centered and whether tails differ by model.",
      "Tracks when HAR plus VIX gains or loses against the HAR benchmark.",
      "Compares model loss across the economically defined regimes with sufficient observations.",
      "Shows signed HAC Diebold-Mariano statistics against HAR; stars mark p < 0.05.",
      "Audits release visibility and median publication lag for every macro series.",
      "Shows the cross-sectional capital buffer in the latest supervisory quarter.",
      "Shows the latest loss-absorbing leverage buffer across banks.",
      "Separates capital weakness from profitability weakness for monitored banks.",
      "Relates CET1 strength to ROA, with asset size and country retained.",
      "Shows the European banking system's median capital path and dispersion.",
      "Shows the system's profitability path and cross-sectional dispersion.",
      "Surfaces the latest names requiring the most monitoring attention.",
      "Compares prediction error for one-, two-, and four-quarter deterioration horizons.",
      "Shows which models add value over the no-deterioration benchmark.",
      "Compares the full cross-section of stressed CET1 outcomes by scenario.",
      "Shows how much evidence supports each of 21 transparent KPI definitions.",
      "Distinguishes deep record counts from broad issuer coverage.",
      "Compares annual and direct-reported quarterly gross margins after robust display limits.",
      "Shows the central mass and tails of operating profitability.",
      "Shows the distribution of comparable-period revenue changes.",
      "Shows capital-structure dispersion without allowing extreme ratios to dominate the view.",
      "Counts every implemented deterioration and anomaly rule.",
      "Counts identity, timing, vintage, and large-restatement quality flags.",
      "Shows whether annual evidence depth expands or contracts through time.",
      "Tracks robust annual medians for four comparable operating KPIs."
    )
  )
}

sample_kpi_values <- function(con, path, kpi, lower, upper, n = 60000L) {
  data.table::as.data.table(DBI::dbGetQuery(con, sprintf(paste(
    "SELECT frequency, value FROM read_parquet(%s)",
    "WHERE kpi = '%s' AND value BETWEEN %f AND %f",
    "ORDER BY hash(CIK, period_end, accession) LIMIT %d"
  ), sql_path(path), kpi, lower, upper, as.integer(n))))
}

write_plot_gallery_html <- function(manifest, report_path) {
  cards <- vapply(seq_len(nrow(manifest)), function(i) {
    row <- manifest[i]
    paste0("<article><img loading='lazy' src='../figures/gallery/", row$slug,
      ".png' alt='", htmltools::htmlEscape(row$title), "'><div class='copy'><div class='meta'>",
      sprintf("%02d", row$number), " · ", htmltools::htmlEscape(row$domain), "</div><h2>",
      htmltools::htmlEscape(row$title), "</h2><p>", htmltools::htmlEscape(row$caption),
      "</p></div></article>")
  }, character(1))
  html <- paste0(
    "<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>",
    "<title>Financial Research — 30-Plot Gallery</title><style>",
    ":root{--navy:#17365d;--blue:#2e75b6;--ink:#17202a;--muted:#5b6775;--line:#dce3ea;--paper:#f5f7fa}",
    "*{box-sizing:border-box}body{margin:0;font-family:Inter,Segoe UI,system-ui,sans-serif;color:var(--ink);background:var(--paper)}",
    "header{background:linear-gradient(120deg,var(--navy),var(--blue));color:white;padding:48px max(24px,calc((100vw - 1420px)/2)) 42px}",
    "header h1{margin:0 0 10px;font-size:clamp(30px,5vw,52px)}header p{max-width:820px;margin:0;line-height:1.55;font-size:17px}",
    "main{max-width:1468px;margin:0 auto;padding:28px 24px 56px;display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px}",
    "article{background:white;border:1px solid var(--line);border-radius:10px;overflow:hidden;box-shadow:0 4px 15px rgba(23,54,93,.07)}",
    "img{width:100%;height:auto;display:block;border-bottom:1px solid var(--line)}.copy{padding:17px 20px 20px}.meta{font-size:12px;font-weight:700;color:var(--blue);text-transform:uppercase;letter-spacing:.08em}",
    "h2{font-size:20px;margin:7px 0;color:var(--navy)}article p{margin:0;color:var(--muted);line-height:1.45}",
    "footer{max-width:1420px;margin:0 auto;padding:0 24px 42px;color:var(--muted)}@media(max-width:820px){main{grid-template-columns:1fr}header{padding:34px 24px}}",
    "</style></head><body><header><h1>30-Plot Financial Research Gallery</h1><p>",
    "Thirty reproducible views spanning point-in-time macro volatility forecasts, European bank capital monitoring, and SEC company fundamentals. Every figure is generated from executed pipeline outputs.</p></header><main>",
    paste(cards, collapse = ""), "</main><footer>Generated by the targets pipeline · ",
    format(Sys.Date(), "%Y-%m-%d"), "</footer></body></html>"
  )
  atomic_write_lines(html, report_path)
}

build_plot_gallery <- function(bank_features, bank_models, bank_stress, macro_model_suite,
                               macro_evaluation, macro_vintage_coverage, accounting_quality,
                               company_kpis, company_anomalies, config) {
  output_dir <- project_path("figures/gallery", root = config$project_root)
  report_path <- project_path("reports/plot_gallery.html", root = config$project_root)
  manifest_path <- project_path("reports/plot_gallery_manifest.csv", root = config$project_root)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  pal <- gallery_palette()
  manifest <- gallery_manifest()
  paths <- character()
  add <- function(plot, number, width = 9, height = 5.4) {
    paths <<- c(paths, save_gallery_plot(plot + gallery_theme(), manifest[number]$slug,
      output_dir, width, height))
  }

  mm <- data.table::copy(macro_evaluation$metrics)
  mm[, horizon_label := factor(paste0(horizon, "d"), levels = paste0(sort(unique(horizon)), "d"))]
  add(ggplot2::ggplot(mm, ggplot2::aes(horizon_label, QLIKE, fill = model)) +
      ggplot2::geom_col(position = ggplot2::position_dodge(width = .82), width = .74) +
      ggplot2::scale_fill_manual(values = rep(pal, length.out = data.table::uniqueN(mm$model))) +
      ggplot2::labs(title = manifest[1]$title, subtitle = manifest[1]$caption,
        x = "Forecast horizon", y = "QLIKE", fill = "Model"), 1)
  add(ggplot2::ggplot(mm, ggplot2::aes(horizon_label, RMSE, colour = model, group = model)) +
      ggplot2::geom_line(linewidth = .8) + ggplot2::geom_point(size = 2.2) +
      ggplot2::scale_colour_manual(values = rep(pal, length.out = data.table::uniqueN(mm$model))) +
      ggplot2::labs(title = manifest[2]$title, subtitle = manifest[2]$caption,
        x = "Forecast horizon", y = "RMSE", colour = "Model"), 2)
  add(ggplot2::ggplot(mm, ggplot2::aes(horizon_label, model, fill = rank_QLIKE)) +
      ggplot2::geom_tile(colour = "white", linewidth = .7) +
      ggplot2::geom_text(ggplot2::aes(label = as.integer(rank_QLIKE)), size = 3.4) +
      ggplot2::scale_fill_gradient(low = "#DCEAF7", high = "#2E75B6", trans = "reverse") +
      ggplot2::labs(title = manifest[3]$title, subtitle = manifest[3]$caption,
        x = "Forecast horizon", y = NULL, fill = "QLIKE rank"), 3)

  mp <- data.table::copy(macro_model_suite$predictions)
  series <- mp[model == "HAR_VIX" & horizon == 22L & is.finite(actual_variance) & is.finite(predicted_variance)]
  series <- utils::tail(series[order(forecast_date)], 650L)
  long <- data.table::melt(series[, .(forecast_date, Realized = actual_variance, Forecast = predicted_variance)],
    id.vars = "forecast_date", variable.name = "series", value.name = "variance")
  add(ggplot2::ggplot(long, ggplot2::aes(forecast_date, variance, colour = series)) +
      ggplot2::geom_line(linewidth = .55) + ggplot2::scale_y_log10() +
      ggplot2::scale_colour_manual(values = pal[c(5, 2)]) +
      ggplot2::labs(title = manifest[4]$title, subtitle = manifest[4]$caption,
        x = NULL, y = "22-day variance (log scale)", colour = NULL), 4)
  calibration <- series[seq(1L, .N, by = max(1L, floor(.N / 1200L)))]
  add(ggplot2::ggplot(calibration, ggplot2::aes(actual_variance, predicted_variance)) +
      ggplot2::geom_abline(slope = 1, intercept = 0, colour = pal[5], linewidth = .7) +
      ggplot2::geom_point(alpha = .42, size = 1.7, colour = pal[2]) +
      ggplot2::scale_x_log10() + ggplot2::scale_y_log10() +
      ggplot2::labs(title = manifest[5]$title, subtitle = manifest[5]$caption,
        x = "Realized 22-day variance (log scale)", y = "Predicted 22-day variance (log scale)"), 5)
  residuals <- mp[horizon == 22L & is.finite(actual) & is.finite(prediction),
    .(model, error = actual - prediction)]
  add(ggplot2::ggplot(residuals, ggplot2::aes(error, colour = model)) +
      ggplot2::geom_density(linewidth = .75, adjust = 1.1) +
      ggplot2::geom_vline(xintercept = 0, colour = "#708090", linewidth = .4) +
      ggplot2::scale_colour_manual(values = rep(pal, length.out = data.table::uniqueN(residuals$model))) +
      ggplot2::coord_cartesian(xlim = stats::quantile(residuals$error, c(.01, .99), na.rm = TRUE)) +
      ggplot2::labs(title = manifest[6]$title, subtitle = manifest[6]$caption,
        x = "Log realized variance − log forecast", y = "Density", colour = "Model"), 6)
  loss <- mp[horizon == 22L & model %in% c("HAR", "HAR_VIX"),
    .(forecast_date, model, actual_variance, predicted_variance)]
  loss[, qloss := log(pmax(predicted_variance, 1e-12)) + actual_variance / pmax(predicted_variance, 1e-12)]
  loss <- data.table::dcast(loss, forecast_date ~ model, value.var = "qloss")
  data.table::setorder(loss, forecast_date)
  loss[, cumulative_advantage := cumsum(HAR - HAR_VIX)]
  add(ggplot2::ggplot(loss, ggplot2::aes(forecast_date, cumulative_advantage)) +
      ggplot2::geom_hline(yintercept = 0, colour = "#708090", linewidth = .4) +
      ggplot2::geom_line(colour = pal[2], linewidth = .75) +
      ggplot2::labs(title = manifest[7]$title, subtitle = manifest[7]$caption,
        x = NULL, y = "Cumulative HAR loss minus HAR + VIX loss"), 7)
  regimes <- data.table::copy(macro_evaluation$regime_metrics)[horizon == 22L]
  add(ggplot2::ggplot(regimes, ggplot2::aes(regime, model, fill = QLIKE)) +
      ggplot2::geom_tile(colour = "white", linewidth = .5) +
      ggplot2::scale_fill_gradient(low = "#DCEAF7", high = "#C43C39") +
      ggplot2::scale_x_discrete(labels = function(x) gsub("_", "\n", x)) +
      ggplot2::labs(title = manifest[8]$title, subtitle = manifest[8]$caption,
        x = NULL, y = NULL, fill = "QLIKE"), 8, 10, 5.8)
  dm <- data.table::copy(macro_evaluation$dm_tests)[is.finite(statistic)]
  dm[, label := paste0(sprintf("%.1f", statistic), data.table::fifelse(p_value < .05, "*", ""))]
  dm[, horizon_label := factor(paste0(horizon, "d"), levels = paste0(sort(unique(horizon)), "d"))]
  dm_limit <- max(abs(dm$statistic), na.rm = TRUE)
  add(ggplot2::ggplot(dm, ggplot2::aes(horizon_label, model, fill = statistic)) +
      ggplot2::geom_tile(colour = "white", linewidth = .6) +
      ggplot2::geom_text(ggplot2::aes(label = label), size = 3) +
      ggplot2::scale_fill_gradient2(low = "#2E75B6", mid = "white", high = "#C43C39",
        midpoint = 0, limits = c(-dm_limit, dm_limit)) +
      ggplot2::labs(title = manifest[9]$title, subtitle = manifest[9]$caption,
        x = "Forecast horizon", y = NULL, fill = "DM statistic"), 9)
  vc <- data.table::copy(macro_vintage_coverage)[is.finite(median_release_lag_days) &
    is.finite(distinct_visible_releases) & is.finite(forecast_dates_covered)]
  add(ggplot2::ggplot(vc, ggplot2::aes(median_release_lag_days, distinct_visible_releases,
        label = series_id)) +
      ggplot2::geom_point(ggplot2::aes(size = forecast_dates_covered), colour = pal[2], alpha = .75) +
      ggplot2::geom_text(check_overlap = TRUE, nudge_y = 4, size = 3) +
      ggplot2::labs(title = manifest[10]$title, subtitle = manifest[10]$caption,
        x = "Median release lag (days)", y = "Distinct visible releases", size = "Forecast dates covered"), 10)

  bank <- data.table::copy(bank_features)
  latest <- bank[quarter == max(quarter, na.rm = TRUE)]
  add(ggplot2::ggplot(latest[is.finite(CET1_model)], ggplot2::aes(100 * CET1_model)) +
      ggplot2::geom_histogram(bins = 24, fill = pal[2], colour = "white") +
      ggplot2::geom_vline(xintercept = 100 * stats::median(latest$CET1_model, na.rm = TRUE),
        colour = pal[5], linewidth = .8) +
      ggplot2::labs(title = manifest[11]$title, subtitle = manifest[11]$caption,
        x = "CET1 ratio (%)", y = "Banks"), 11)
  add(ggplot2::ggplot(latest[is.finite(leverage_ratio_model)],
        ggplot2::aes(100 * leverage_ratio_model)) +
      ggplot2::geom_histogram(bins = 24, fill = pal[3], colour = "white") +
      ggplot2::geom_vline(xintercept = 100 * stats::median(latest$leverage_ratio_model, na.rm = TRUE),
        colour = pal[5], linewidth = .8) +
      ggplot2::labs(title = manifest[12]$title, subtitle = manifest[12]$caption,
        x = "Leverage ratio (%)", y = "Banks"), 12)
  risk_sample <- latest[is.finite(capital_risk_score) & is.finite(profitability_risk_score) &
    is.finite(overall_risk_score) & is.finite(total_assets)]
  risk_labels <- risk_sample[!is.na(bank_name) & nzchar(bank_name)][order(-overall_risk_score)]
  risk_labels <- risk_labels[seq_len(min(10L, .N))]
  add(ggplot2::ggplot(risk_sample, ggplot2::aes(capital_risk_score, profitability_risk_score)) +
      ggplot2::geom_hline(yintercept = 0, colour = "#B7C1CC", linewidth = .4) +
      ggplot2::geom_vline(xintercept = 0, colour = "#B7C1CC", linewidth = .4) +
      ggplot2::geom_point(ggplot2::aes(size = total_assets, colour = overall_risk_score), alpha = .65) +
      ggplot2::geom_text(data = risk_labels, ggplot2::aes(label = bank_name),
        check_overlap = TRUE, size = 2.7, nudge_y = .08) +
      ggplot2::scale_colour_gradient(low = pal[2], high = pal[5]) +
      ggplot2::labs(title = manifest[13]$title, subtitle = manifest[13]$caption,
        x = "Capital risk z-score", y = "Profitability risk z-score", size = "Assets",
        colour = "Overall score"), 13)
  top_countries <- latest[, .N, by = country][order(-N)][seq_len(min(8L, .N)), country]
  capital_profit <- latest[country %in% top_countries & is.finite(CET1_model) &
    is.finite(ROA) & is.finite(total_assets)]
  add(ggplot2::ggplot(capital_profit,
        ggplot2::aes(100 * CET1_model, 100 * ROA, colour = country, size = total_assets)) +
      ggplot2::geom_point(alpha = .65) +
      ggplot2::scale_colour_manual(values = rep(pal, length.out = length(top_countries))) +
      ggplot2::labs(title = manifest[14]$title, subtitle = manifest[14]$caption,
        x = "CET1 ratio (%)", y = "ROA (%)", colour = "Country", size = "Assets"), 14)
  bank_trend <- bank[, .(
    cet1_p25 = stats::quantile(CET1_model, .25, na.rm = TRUE),
    cet1_median = stats::median(CET1_model, na.rm = TRUE),
    cet1_p75 = stats::quantile(CET1_model, .75, na.rm = TRUE),
    roa_p25 = stats::quantile(ROA, .25, na.rm = TRUE),
    roa_median = stats::median(ROA, na.rm = TRUE),
    roa_p75 = stats::quantile(ROA, .75, na.rm = TRUE)), by = quarter]
  add(ggplot2::ggplot(bank_trend, ggplot2::aes(quarter, 100 * cet1_median)) +
      ggplot2::geom_ribbon(ggplot2::aes(ymin = 100 * cet1_p25, ymax = 100 * cet1_p75),
        fill = pal[2], alpha = .18) + ggplot2::geom_line(colour = pal[2], linewidth = .85) +
      ggplot2::labs(title = manifest[15]$title, subtitle = manifest[15]$caption,
        x = NULL, y = "CET1 ratio (%)"), 15)
  add(ggplot2::ggplot(bank_trend, ggplot2::aes(quarter, 100 * roa_median)) +
      ggplot2::geom_ribbon(ggplot2::aes(ymin = 100 * roa_p25, ymax = 100 * roa_p75),
        fill = pal[3], alpha = .18) + ggplot2::geom_line(colour = pal[3], linewidth = .85) +
      ggplot2::labs(title = manifest[16]$title, subtitle = manifest[16]$caption,
        x = NULL, y = "ROA (%)"), 16)
  top_risk <- utils::head(latest[is.finite(overall_risk_score) & !is.na(bank_name) &
    nzchar(bank_name)][order(-overall_risk_score)], 20L)
  top_risk[, label := factor(substr(bank_name, 1L, 38L), levels = rev(substr(bank_name, 1L, 38L)))]
  add(ggplot2::ggplot(top_risk, ggplot2::aes(overall_risk_score, label)) +
      ggplot2::geom_col(fill = pal[5], width = .7) +
      ggplot2::labs(title = manifest[17]$title, subtitle = manifest[17]$caption,
        x = "Overall monitoring score", y = NULL), 17, 9, 7)
  bm <- data.table::copy(bank_models$metrics)
  bm[, horizon_label := factor(paste0(horizon, "q"), levels = paste0(sort(unique(horizon)), "q"))]
  add(ggplot2::ggplot(bm, ggplot2::aes(horizon_label, RMSE, fill = model)) +
      ggplot2::geom_col(position = ggplot2::position_dodge(width = .82), width = .72) +
      ggplot2::scale_fill_manual(values = rep(pal, length.out = data.table::uniqueN(bm$model))) +
      ggplot2::labs(title = manifest[18]$title, subtitle = manifest[18]$caption,
        x = "Forecast horizon", y = "RMSE", fill = "Model"), 18)
  add(ggplot2::ggplot(bm, ggplot2::aes(model, R2_OOS, colour = horizon_label)) +
      ggplot2::geom_hline(yintercept = 0, colour = "#708090", linewidth = .45) +
      ggplot2::geom_point(position = ggplot2::position_dodge(width = .45), size = 2.5) +
      ggplot2::scale_colour_manual(values = pal[c(2, 3, 5)]) +
      ggplot2::labs(title = manifest[19]$title, subtitle = manifest[19]$caption,
        x = NULL, y = "Out-of-sample R²", colour = "Horizon") +
      ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 30, hjust = 1)), 19)
  stress <- data.table::copy(bank_stress$results)[is.finite(stressed_CET1)]
  add(ggplot2::ggplot(stress, ggplot2::aes(scenario, 100 * stressed_CET1, fill = scenario)) +
      ggplot2::geom_boxplot(outlier.alpha = .25, width = .62) +
      ggplot2::scale_fill_manual(values = rep(pal, length.out = data.table::uniqueN(stress$scenario))) +
      ggplot2::labs(title = manifest[20]$title, subtitle = manifest[20]$caption,
        x = NULL, y = "Stressed CET1 ratio (%)", fill = NULL) +
      ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 22, hjust = 1),
        legend.position = "none"), 20, 10, 5.8)

  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  kpi_path <- company_kpis$kpis_path
  coverage <- data.table::as.data.table(DBI::dbGetQuery(con, sprintf(paste(
    "SELECT kpi, frequency, count(*) AS records, count(DISTINCT CIK) AS companies",
    "FROM read_parquet(%s) GROUP BY kpi, frequency"
  ), sql_path(kpi_path))))
  coverage[, kpi_label := gsub("_", " ", kpi)]
  coverage[, kpi_label := factor(kpi_label, levels = unique(kpi_label[order(records)]))]
  add(ggplot2::ggplot(coverage, ggplot2::aes(records, kpi_label, fill = frequency)) +
      ggplot2::geom_col(position = "dodge") +
      ggplot2::scale_fill_manual(values = pal[c(2, 4)]) +
      ggplot2::scale_x_continuous(labels = function(x) format(x, big.mark = ",", scientific = FALSE)) +
      ggplot2::labs(title = manifest[21]$title, subtitle = manifest[21]$caption,
        x = "KPI records", y = NULL, fill = "Frequency"), 21, 10, 8)
  coverage[, company_label := factor(gsub("_", " ", kpi),
    levels = unique(gsub("_", " ", kpi)[order(companies)]))]
  add(ggplot2::ggplot(coverage, ggplot2::aes(companies, company_label, colour = frequency)) +
      ggplot2::geom_point(position = ggplot2::position_dodge(width = .55), size = 2.4) +
      ggplot2::scale_colour_manual(values = pal[c(2, 4)]) +
      ggplot2::scale_x_continuous(labels = function(x) format(x, big.mark = ",", scientific = FALSE)) +
      ggplot2::labs(title = manifest[22]$title, subtitle = manifest[22]$caption,
        x = "Distinct companies", y = NULL, colour = "Frequency"), 22, 10, 8)

  add_distribution <- function(kpi, limits, number, x_label) {
    values <- sample_kpi_values(con, kpi_path, kpi, limits[[1L]], limits[[2L]])
    plot <- ggplot2::ggplot(values, ggplot2::aes(value, fill = frequency)) +
      ggplot2::geom_histogram(bins = 55, position = "identity", alpha = .52) +
      ggplot2::scale_fill_manual(values = pal[c(2, 4)]) +
      ggplot2::labs(title = manifest[number]$title, subtitle = manifest[number]$caption,
        x = x_label, y = "Sampled records", fill = "Frequency")
    add(plot, number)
  }
  add_distribution("gross_margin", c(-1, 1.5), 23, "Gross margin")
  add_distribution("operating_margin", c(-1, 1), 24, "Operating margin")
  add_distribution("revenue_growth", c(-1, 2), 25, "Comparable-period revenue growth")
  add_distribution("debt_to_equity", c(-5, 10), 26, "Debt to equity")

  anomaly <- data.table::as.data.table(DBI::dbGetQuery(con, sprintf(paste(
    "SELECT sum(CAST(revenue_down_sharply AS INTEGER)) AS revenue_down_sharply,",
    "sum(CAST(cfo_deterioration AS INTEGER)) AS cfo_deterioration,",
    "sum(CAST(margin_collapse AS INTEGER)) AS margin_collapse,",
    "sum(CAST(leverage_spike AS INTEGER)) AS leverage_spike,",
    "sum(CAST(interest_coverage_collapse AS INTEGER)) AS interest_coverage_collapse,",
    "sum(CAST(unusual_accruals AS INTEGER)) AS unusual_accruals",
    "FROM read_parquet(%s)"
  ), sql_path(company_anomalies))))
  anomaly <- data.table::melt(anomaly, measure.vars = names(anomaly),
    variable.name = "flag", value.name = "count")
  anomaly[, flag := factor(gsub("_", " ", flag), levels = gsub("_", " ", flag)[order(count)])]
  add(ggplot2::ggplot(anomaly, ggplot2::aes(count, flag)) +
      ggplot2::geom_col(fill = pal[5], width = .7) +
      ggplot2::labs(title = manifest[27]$title, subtitle = manifest[27]$caption,
        x = "Flagged company-periods", y = NULL), 27)
  aq <- data.table::as.data.table(DBI::dbGetQuery(con, sprintf(paste(
    "SELECT sum(CAST(identity_flag AS INTEGER)) AS identity_break,",
    "sum(CAST(malformed_period_flag AS INTEGER)) AS malformed_period,",
    "sum(CAST(malformed_available_flag AS INTEGER)) AS malformed_available,",
    "sum(CAST(future_period_flag AS INTEGER)) AS future_period,",
    "sum(CAST(period_after_filing_flag AS INTEGER)) AS period_after_filing,",
    "sum(CAST(duplicate_vintage_flag AS INTEGER)) AS duplicate_vintage,",
    "sum(CAST(restatement_change_pct > 0.1 AS INTEGER)) AS large_restatement",
    "FROM read_parquet(%s)"
  ), sql_path(accounting_quality$flags_path))))
  aq <- data.table::melt(aq, measure.vars = names(aq),
    variable.name = "flag", value.name = "count")
  aq[, flag := factor(gsub("_", " ", flag), levels = gsub("_", " ", flag)[order(count)])]
  add(ggplot2::ggplot(aq, ggplot2::aes(count, flag)) +
      ggplot2::geom_col(fill = pal[4], width = .7) +
      ggplot2::labs(title = manifest[28]$title, subtitle = manifest[28]$caption,
        x = "Flagged records", y = NULL), 28)

  selected_kpis <- c("revenue_growth", "gross_margin", "operating_margin", "cfo_margin")
  selected_sql <- paste(sprintf("'%s'", selected_kpis), collapse = ",")
  trends <- data.table::as.data.table(DBI::dbGetQuery(con, sprintf(paste(
    "SELECT year(TRY_CAST(period_end AS DATE)) AS year, kpi, count(*) AS records,",
    "median(value) AS median_value FROM read_parquet(%s)",
    "WHERE frequency='annual' AND kpi IN (%s)",
    "AND year(TRY_CAST(period_end AS DATE)) BETWEEN 2008 AND 2025",
    "GROUP BY year, kpi ORDER BY year, kpi"
  ), sql_path(kpi_path), selected_sql)))
  trends[, kpi_label := gsub("_", " ", kpi)]
  add(ggplot2::ggplot(trends, ggplot2::aes(year, records, colour = kpi_label)) +
      ggplot2::geom_line(linewidth = .8) +
      ggplot2::scale_colour_manual(values = pal[seq_along(selected_kpis)]) +
      ggplot2::labs(title = manifest[29]$title, subtitle = manifest[29]$caption,
        x = "Fiscal year", y = "Annual KPI records", colour = "KPI"), 29)
  add(ggplot2::ggplot(trends, ggplot2::aes(year, median_value)) +
      ggplot2::geom_hline(yintercept = 0, colour = "#B7C1CC", linewidth = .35) +
      ggplot2::geom_line(colour = pal[2], linewidth = .8) +
      ggplot2::facet_wrap(~kpi_label, scales = "free_y", ncol = 2) +
      ggplot2::labs(title = manifest[30]$title, subtitle = manifest[30]$caption,
        x = "Fiscal year", y = "Median value"), 30, 10, 7)

  manifest[, file := paste0("figures/gallery/", slug, ".png")]
  data.table::fwrite(manifest, manifest_path)
  html_path <- write_plot_gallery_html(manifest, report_path)
  if (length(paths) != 30L || anyDuplicated(paths) || !all(file.exists(paths))) {
    stop("Plot gallery must contain exactly 30 unique existing PNG files")
  }
  normalizePath(c(paths, manifest_path, html_path), winslash = "/", mustWork = TRUE)
}
