library(targets)

tar_option_set(
  packages = c("data.table", "jsonlite", "htmltools", "checkmate", "knitr"),
  seed = 20260813,
  error = "stop"
)

tar_source("R")

list(
  tar_target(demo_config_file, "config_demo.yml", format = "file"),
  tar_target(demo_config, yaml::read_yaml(demo_config_file)$demo),
  tar_target(demo_inputs, read_demo_inputs(demo_config)),
  tar_target(demo_macro, run_demo_macro(demo_inputs$macro, demo_config)),
  tar_target(demo_bank, summarize_demo_bank(demo_inputs$bank)),
  tar_target(demo_fundamentals, summarize_demo_fundamentals(demo_inputs$fundamentals)),
  tar_target(demo_report,
    write_demo_report(demo_macro, demo_bank, demo_fundamentals, demo_config),
    format = "file")
)
