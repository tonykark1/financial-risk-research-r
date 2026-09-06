`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0L) y else x
}

project_config <- function(path = "config.yml", profile = "default") {
  cfg <- yaml::read_yaml(path)
  out <- cfg[[profile]] %||% cfg
  out$project_root <- normalizePath(dirname(path), winslash = "/", mustWork = TRUE)
  upstream_root <- Sys.getenv(
    "FINANCIAL_RESEARCH_UPSTREAM_ROOT",
    unset = out$upstream_root
  )
  if (!grepl("^([A-Za-z]:[/\\\\]|/)", upstream_root)) {
    upstream_root <- file.path(out$project_root, upstream_root)
  }
  out$upstream_root <- normalizePath(upstream_root, winslash = "/", mustWork = TRUE)
  out
}

project_path <- function(..., root = getwd()) {
  normalizePath(file.path(root, ...), winslash = "/", mustWork = FALSE)
}

ensure_project_directories <- function(root = getwd()) {
  paths <- c(
    "R/bank_risk", "R/macro_vol", "R/fundamentals",
    "data/raw", "data/bronze", "data/silver", "data/gold",
    "data/gold/bank_risk", "data/gold/macro_vol", "data/gold/fundamentals",
    "data/snapshots", "database", "reports/bank_risk", "reports/macro_vol",
    "reports/fundamentals", "reports/diagnostics", "figures/bank_risk",
    "figures/macro_vol", "figures/fundamentals", "figures/gallery", "tables/bank_risk",
    "tables/macro_vol", "tables/fundamentals", "tests/testthat", "notebooks",
    "logs", "docs", "sql"
  )
  invisible(vapply(file.path(root, paths), dir.create, logical(1),
    recursive = TRUE, showWarnings = FALSE
  ))
}

log_event <- function(module, dataset = NA_character_, entity = NA_character_,
                      status = "ok", warning = NA_character_, error = NA_character_,
                      runtime = NA_real_, log_file = "logs/pipeline.csv") {
  dir.create(dirname(log_file), recursive = TRUE, showWarnings = FALSE)
  event <- data.table::data.table(
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3%z"),
    module = as.character(module), dataset = as.character(dataset),
    entity = as.character(entity), status = as.character(status),
    warning = as.character(warning), error = as.character(error),
    runtime_seconds = as.numeric(runtime)
  )
  data.table::fwrite(event, log_file, append = file.exists(log_file))
  invisible(event)
}

with_logged_step <- function(module, dataset = NA_character_, code) {
  started <- proc.time()[["elapsed"]]
  tryCatch({
    value <- force(code)
    log_event(module, dataset, runtime = proc.time()[["elapsed"]] - started)
    value
  }, warning = function(w) {
    log_event(module, dataset, status = "warning", warning = conditionMessage(w),
      runtime = proc.time()[["elapsed"]] - started
    )
    invokeRestart("muffleWarning")
  }, error = function(e) {
    log_event(module, dataset, status = "error", error = conditionMessage(e),
      runtime = proc.time()[["elapsed"]] - started
    )
    stop(e)
  })
}

safe_divide <- function(numerator, denominator, minimum = 1e-12) {
  out <- rep(NA_real_, max(length(numerator), length(denominator)))
  good <- is.finite(numerator) & is.finite(denominator) & abs(denominator) > minimum
  out[good] <- numerator[good] / denominator[good]
  out
}

atomic_write_lines <- function(text, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- tempfile(pattern = basename(path), tmpdir = dirname(path))
  writeLines(text, tmp, useBytes = TRUE)
  if (file.exists(path)) unlink(path)
  if (!file.rename(tmp, path)) stop("Could not atomically write ", path)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

