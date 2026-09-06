library(targets)
library(yaml)
library(jsonlite)

config <- read_yaml("config_demo.yml")$demo
store <- Sys.getenv("DEMO_TARGETS_STORE", unset = "_targets_demo")
outdated_before <- tar_outdated(script = "_targets_demo.R", store = store)
started <- proc.time()[["elapsed"]]
tar_make(script = "_targets_demo.R", store = store, callr_function = NULL)
elapsed <- proc.time()[["elapsed"]] - started
dir.create(config$output_directory, recursive = TRUE, showWarnings = FALSE)
manifest <- list(
  status = "completed",
  elapsed_seconds = unname(elapsed),
  targets_outdated_before = length(outdated_before),
  cache_state = if (length(outdated_before)) "build_required" else "up_to_date",
  maximum_runtime_seconds = config$maximum_runtime_seconds,
  within_runtime_contract = elapsed <= config$maximum_runtime_seconds,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
)
write_json(manifest, file.path(config$output_directory, "runtime.json"),
  auto_unbox = TRUE, pretty = TRUE)
if (!manifest$within_runtime_contract) {
  stop(sprintf("Demo exceeded the %s-second contract: %.1f seconds",
    config$maximum_runtime_seconds, elapsed))
}
cat(sprintf("Demo completed in %.1f seconds\n", elapsed))
