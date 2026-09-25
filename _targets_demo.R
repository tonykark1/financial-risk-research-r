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
  tar_target(demo_input, read_demo_input(demo_config)),
  tar_target(demo_macro, run_demo_macro(demo_input, demo_config)),
  tar_target(
    demo_report,
    write_demo_report(demo_macro, demo_config),
    format = "file"
  )
)
