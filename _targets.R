library(targets)

tar_option_set(
  packages = c(
    "data.table", "DBI", "duckdb", "jsonlite", "yaml", "checkmate",
    "digest", "ggplot2", "slider", "sandwich", "lmtest", "glmnet",
    "ranger", "xgboost", "htmltools", "knitr"
  ),
  format = "rds",
  seed = 20260813,
  error = "stop"
)

tar_source("R")

list(
  tar_target(config_file, "config.yml", format = "file"),
  tar_target(config, project_config(config_file)),
  tar_target(project_directories, ensure_project_directories(config$project_root)),
  tar_target(macro_data, build_macro_forecast_panel(config)),
  tar_target(macro_vintage_coverage, build_macro_vintage_coverage(macro_data, config)),
  tar_target(macro_model_suite, run_macro_model_suite(macro_data, config)),
  tar_target(macro_evaluation, evaluate_macro_models(macro_model_suite, config)),
  tar_target(macro_importance, run_macro_feature_stability(macro_data, config)),
  tar_target(
    public_results,
    write_public_macro_results(macro_evaluation, macro_vintage_coverage,
      macro_model_suite$predictions, config),
    format = "file"
  ),
  tar_target(
    macro_figures,
    build_macro_gallery(macro_model_suite, macro_evaluation,
      macro_vintage_coverage, config),
    format = "file"
  ),
  tar_target(
    macro_report,
    {
      public_results
      macro_figures
      write_macro_report(macro_evaluation, macro_vintage_coverage,
        macro_model_suite$predictions, config)
    },
    format = "file"
  ),
  tar_target(
    test_files,
    list.files("tests/testthat", pattern = "\\.R$", full.names = TRUE),
    format = "file"
  ),
  tar_target(test_results, { test_files; run_test_suite() }, format = "file")
)
