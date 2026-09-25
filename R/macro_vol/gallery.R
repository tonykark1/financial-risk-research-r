macro_gallery_manifest <- function() {
  data.table::data.table(
    number = seq_len(10L),
    slug = c(
      "01-macro-qlike-by-horizon", "02-macro-rmse-by-horizon",
      "03-macro-model-rank-heatmap", "04-macro-actual-vs-forecast",
      "05-macro-forecast-calibration", "06-macro-residual-distribution",
      "07-macro-cumulative-loss-difference", "08-macro-regime-heatmap",
      "09-macro-dm-significance", "10-macro-vintage-coverage"
    ),
    title = c(
      "Forecast QLIKE by horizon", "Forecast RMSE by horizon",
      "Model rank consistency", "Actual versus 22-day forecast",
      "22-day forecast calibration", "22-day log-error distribution",
      "Cumulative loss versus HAR", "Performance across stress regimes",
      "Diebold-Mariano comparison", "Vintage-coverage audit"
    ),
    caption = c(
      "Compares variance-forecast loss across the seven tested specifications.",
      "Shows level-error trade-offs that QLIKE alone can conceal.",
      "Shows whether model leadership is stable across forecast horizons.",
      "Places HAR plus VIX against the close-to-close variance proxy through time.",
      "Checks dispersion and extreme-event calibration on log scales.",
      "Shows the distribution of log forecast errors by model.",
      "Tracks when HAR plus VIX gains or loses against HAR.",
      "Compares 22-day QLIKE across predefined economic regimes.",
      "Shows HAC test statistics against HAR; stars are nominal p < 0.05.",
      "Audits release visibility and publication lags for the macro series."
    )
  )
}

macro_gallery_palette <- function() {
  c("#17365D", "#2E75B6", "#00A6A6", "#F2A900", "#C43C39", "#6F4E7C", "#708090")
}

macro_gallery_theme <- function(base_size = 11) {
  research_theme(base_size) + ggplot2::theme(
    plot.title = ggplot2::element_text(face = "bold", colour = "#17365D",
      size = base_size + 3),
    plot.subtitle = ggplot2::element_text(colour = "#4C5B6B",
      margin = ggplot2::margin(b = 10)),
    axis.title = ggplot2::element_text(face = "bold"),
    panel.grid.major = ggplot2::element_line(colour = "#E4E9EF", linewidth = 0.3)
  )
}

save_macro_plot <- function(plot, slug, directory, width = 9, height = 5.4) {
  path <- file.path(directory, paste0(slug, ".png"))
  ggplot2::ggsave(path, plot, width = width, height = height, dpi = 160, bg = "white")
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

build_macro_gallery <- function(model_suite, evaluation, vintage_coverage, config) {
  output_dir <- project_path("figures/macro_gallery", root = config$project_root)
  manifest_path <- project_path("results/figure_manifest.csv", root = config$project_root)
  benchmark_dir <- project_path("figures", root = config$project_root)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(manifest_path), recursive = TRUE, showWarnings = FALSE)
  dir.create(benchmark_dir, recursive = TRUE, showWarnings = FALSE)
  manifest <- macro_gallery_manifest()
  pal <- macro_gallery_palette()
  paths <- character()
  add <- function(plot, number, width = 9, height = 5.4) {
    paths <<- c(paths, save_macro_plot(
      plot + macro_gallery_theme(), manifest[number]$slug, output_dir, width, height
    ))
  }

  mm <- data.table::copy(evaluation$metrics)
  mm[, horizon_label := factor(paste0(horizon, "d"),
    levels = paste0(sort(unique(horizon)), "d"))]
  har_loss <- mm[model == "HAR", .(horizon, HAR_QLIKE = QLIKE)]
  relative <- merge(mm, har_loss, by = "horizon", all.x = TRUE)
  relative[, QLIKE_difference := QLIKE - HAR_QLIKE]
  benchmark_path <- save_macro_plot(
    ggplot2::ggplot(relative[model != "HAR"],
      ggplot2::aes(horizon_label, QLIKE_difference, fill = model)) +
      ggplot2::geom_hline(yintercept = 0, colour = "#708090", linewidth = .45) +
      ggplot2::geom_col(position = ggplot2::position_dodge(width = .82), width = .74) +
      ggplot2::scale_fill_manual(values = rep(pal,
        length.out = data.table::uniqueN(relative$model) - 1L)) +
      ggplot2::labs(title = "Forecast loss relative to HAR",
        subtitle = "Negative values indicate lower average QLIKE than the HAR baseline",
        x = "Forecast horizon", y = "QLIKE difference versus HAR", fill = "Model") +
      macro_gallery_theme(),
    "benchmark-relative-qlike", benchmark_dir, width = 9, height = 5.4)
  add(ggplot2::ggplot(mm, ggplot2::aes(horizon_label, QLIKE, fill = model)) +
    ggplot2::geom_col(position = ggplot2::position_dodge(width = .82), width = .74) +
    ggplot2::scale_fill_manual(values = rep(pal, length.out = data.table::uniqueN(mm$model))) +
    ggplot2::labs(title = manifest[1]$title, subtitle = manifest[1]$caption,
      x = "Forecast horizon", y = "QLIKE (lower is better)", fill = "Model"), 1)

  add(ggplot2::ggplot(mm, ggplot2::aes(horizon_label, RMSE, colour = model,
      group = model)) +
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

  mp <- data.table::copy(model_suite$predictions)
  series <- mp[model == "HAR_VIX" & horizon == 22L &
    is.finite(actual_variance) & is.finite(predicted_variance)]
  series <- utils::tail(series[order(forecast_date)], 650L)
  long <- data.table::melt(
    series[, .(forecast_date, Realized = actual_variance, Forecast = predicted_variance)],
    id.vars = "forecast_date", variable.name = "series", value.name = "variance"
  )
  add(ggplot2::ggplot(long, ggplot2::aes(forecast_date, variance, colour = series)) +
    ggplot2::geom_line(linewidth = .55) + ggplot2::scale_y_log10() +
    ggplot2::scale_colour_manual(values = pal[c(5, 2)]) +
    ggplot2::labs(title = manifest[4]$title, subtitle = manifest[4]$caption,
      x = NULL, y = "22-day variance proxy (log scale)", colour = NULL), 4)

  calibration <- series[seq(1L, .N, by = max(1L, floor(.N / 1200L)))]
  add(ggplot2::ggplot(calibration,
      ggplot2::aes(actual_variance, predicted_variance)) +
    ggplot2::geom_abline(slope = 1, intercept = 0, colour = pal[5], linewidth = .7) +
    ggplot2::geom_point(alpha = .42, size = 1.7, colour = pal[2]) +
    ggplot2::scale_x_log10() + ggplot2::scale_y_log10() +
    ggplot2::labs(title = manifest[5]$title, subtitle = manifest[5]$caption,
      x = "Observed 22-day variance proxy", y = "Predicted 22-day variance"), 5)

  residuals <- mp[horizon == 22L & is.finite(actual) & is.finite(prediction),
    .(model, error = actual - prediction)]
  add(ggplot2::ggplot(residuals, ggplot2::aes(error, colour = model)) +
    ggplot2::geom_density(linewidth = .75, adjust = 1.1) +
    ggplot2::geom_vline(xintercept = 0, colour = "#708090", linewidth = .4) +
    ggplot2::scale_colour_manual(values = rep(pal,
      length.out = data.table::uniqueN(residuals$model))) +
    ggplot2::coord_cartesian(xlim = stats::quantile(residuals$error,
      c(.01, .99), na.rm = TRUE)) +
    ggplot2::labs(title = manifest[6]$title, subtitle = manifest[6]$caption,
      x = "Log observed variance - log forecast", y = "Density", colour = "Model"), 6)

  loss <- mp[horizon == 22L & model %in% c("HAR", "HAR_VIX"),
    .(forecast_date, model, actual_variance, predicted_variance)]
  loss[, qloss := log(pmax(predicted_variance, 1e-12)) +
    actual_variance / pmax(predicted_variance, 1e-12)]
  loss <- data.table::dcast(loss, forecast_date ~ model, value.var = "qloss")
  data.table::setorder(loss, forecast_date)
  loss[, cumulative_advantage := cumsum(HAR - HAR_VIX)]
  add(ggplot2::ggplot(loss, ggplot2::aes(forecast_date, cumulative_advantage)) +
    ggplot2::geom_hline(yintercept = 0, colour = "#708090", linewidth = .4) +
    ggplot2::geom_line(colour = pal[2], linewidth = .75) +
    ggplot2::labs(title = manifest[7]$title, subtitle = manifest[7]$caption,
      x = NULL, y = "Cumulative HAR loss minus HAR + VIX loss"), 7)

  regimes <- data.table::copy(evaluation$regime_metrics)[horizon == 22L]
  add(ggplot2::ggplot(regimes, ggplot2::aes(regime, model, fill = QLIKE)) +
    ggplot2::geom_tile(colour = "white", linewidth = .5) +
    ggplot2::scale_fill_gradient(low = "#DCEAF7", high = "#C43C39") +
    ggplot2::scale_x_discrete(labels = function(x) gsub("_", "\n", x)) +
    ggplot2::labs(title = manifest[8]$title, subtitle = manifest[8]$caption,
      x = NULL, y = NULL, fill = "QLIKE"), 8, 10, 5.8)

  dm <- data.table::copy(evaluation$dm_tests)[is.finite(statistic)]
  dm[, label := paste0(sprintf("%.1f", statistic),
    data.table::fifelse(p_value < .05, "*", ""))]
  dm[, horizon_label := factor(paste0(horizon, "d"),
    levels = paste0(sort(unique(horizon)), "d"))]
  dm_limit <- max(abs(dm$statistic), na.rm = TRUE)
  add(ggplot2::ggplot(dm, ggplot2::aes(horizon_label, model, fill = statistic)) +
    ggplot2::geom_tile(colour = "white", linewidth = .6) +
    ggplot2::geom_text(ggplot2::aes(label = label), size = 3) +
    ggplot2::scale_fill_gradient2(low = "#2E75B6", mid = "white", high = "#C43C39",
      midpoint = 0, limits = c(-dm_limit, dm_limit)) +
    ggplot2::labs(title = manifest[9]$title, subtitle = manifest[9]$caption,
      x = "Forecast horizon", y = NULL, fill = "DM statistic"), 9)

  vc <- data.table::copy(vintage_coverage)[is.finite(median_release_lag_days) &
    is.finite(distinct_visible_releases) & is.finite(forecast_dates_covered)]
  add(ggplot2::ggplot(vc,
      ggplot2::aes(median_release_lag_days, distinct_visible_releases,
        label = series_id)) +
    ggplot2::geom_point(ggplot2::aes(size = forecast_dates_covered),
      colour = pal[2], alpha = .75) +
    ggplot2::geom_text(check_overlap = TRUE, nudge_y = 4, size = 3) +
    ggplot2::labs(title = manifest[10]$title, subtitle = manifest[10]$caption,
      x = "Median release lag (days)", y = "Distinct visible releases",
      size = "Forecast dates covered"), 10)

  manifest[, file := paste0("figures/macro_gallery/", slug, ".png")]
  data.table::fwrite(manifest, manifest_path)
  if (length(paths) != 10L || anyDuplicated(paths) || !all(file.exists(paths))) {
    stop("Macro gallery must contain exactly 10 unique existing PNG files")
  }
  normalizePath(c(benchmark_path, paths, manifest_path), winslash = "/", mustWork = TRUE)
}
