library(targets)

tar_option_set(
  packages = c(
    "data.table", "DBI", "duckdb", "jsonlite", "yaml", "checkmate",
    "digest", "ggplot2", "slider", "sandwich", "lmtest", "glmnet",
    "ranger", "xgboost", "fixest", "future", "furrr", "htmltools", "knitr"
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
  tar_target(upstream_views, register_upstream_views(config)),
  tar_target(repository_inventory, repository_file_inventory(config)),
  tar_target(
    repository_inventory_file,
    write_parquet_duckdb(repository_inventory, "data/gold/repository_file_inventory.parquet"),
    format = "file"
  ),
  tar_target(data_catalog, build_data_catalog(config)),
  tar_target(
    data_catalog_file,
    write_parquet_duckdb(data_catalog, "data/gold/data_catalog.parquet"),
    format = "file"
  ),
  tar_target(
    data_inventory_report,
    render_data_inventory(data_catalog, "reports/data_inventory.html"),
    format = "file"
  ),
  tar_target(entity_layer, build_entity_layer(config)),
  tar_target(
    entity_layer_files,
    { entity_layer; c("data/gold/entity_master.parquet", "data/gold/identifier_crosswalk.parquet") },
    format = "file"
  ),
  tar_target(
    entity_mapping_report,
    render_entity_mapping_report(entity_layer, "reports/entity_mapping_report.html"),
    format = "file"
  ),
  tar_target(bank_panel, build_bank_quarterly_panel(config)),
  tar_target(bank_quality, bank_data_quality(bank_panel, config)),
  tar_target(bank_features, score_bank_risk(bank_panel, config)),
  tar_target(bank_models, run_bank_models(bank_features, config)),
  tar_target(bank_importance, run_bank_feature_importance(bank_features, config)),
  tar_target(macro_data, build_macro_forecast_panel(config)),
  tar_target(macro_vintage_coverage, build_macro_vintage_coverage(macro_data, config)),
  tar_target(macro_model_suite, run_macro_model_suite(macro_data, config)),
  tar_target(macro_evaluation, evaluate_macro_models(macro_model_suite, config)),
  tar_target(macro_importance, run_macro_feature_stability(macro_data, config)),
  tar_target(bank_stress, run_bank_stress_scenarios(bank_features, macro_data, config)),
  tar_target(
    bank_reports,
    render_bank_reports(bank_features, bank_quality, bank_models, bank_stress,
      config, bank_importance),
    format = "file"
  ),
  tar_target(
    macro_reports,
    render_macro_reports(macro_model_suite, macro_evaluation, config, macro_importance,
      macro_vintage_coverage),
    format = "file"
  ),
  tar_target(fundamentals, build_fundamentals_data(config)),
  tar_target(accounting_quality, build_accounting_quality(fundamentals, config)),
  tar_target(company_kpis, build_company_kpis(fundamentals, config)),
  tar_target(company_anomalies, build_company_anomalies(company_kpis, config), format = "file"),
  tar_target(peer_analysis, build_peer_analysis(fundamentals, company_kpis, config)),
  tar_target(
    fundamentals_reports,
    render_fundamentals_reports(fundamentals, accounting_quality, company_kpis,
      company_anomalies, peer_analysis, config),
    format = "file"
  ),
  tar_target(
    plot_gallery,
    {
      bank_reports
      macro_reports
      fundamentals_reports
      build_plot_gallery(bank_features, bank_models, bank_stress, macro_model_suite,
        macro_evaluation, macro_vintage_coverage, accounting_quality, company_kpis,
        company_anomalies, config)
    },
    format = "file"
  ),
  tar_target(
    case_study_assets,
    {
      plot_gallery
      build_case_study_assets(macro_evaluation, bank_features, bank_stress,
        accounting_quality, company_kpis, config)
    },
    format = "file"
  ),
  tar_target(
    cv_metrics,
    collect_cv_metrics(config, bank_features, macro_data, macro_model_suite,
      fundamentals, company_kpis, entity_layer)
  ),
  tar_target(cv_metrics_file, write_cv_metrics(cv_metrics), format = "file"),
  tar_target(
    interview_notes,
    write_interview_notes(bank_models, macro_evaluation, accounting_quality, config),
    format = "file"
  ),
  tar_target(
    final_audit,
    write_final_audit(cv_metrics, bank_models, macro_evaluation, accounting_quality),
    format = "file"
  ),
  tar_target(
    execution_logs,
    write_execution_logs(bank_quality, bank_models, macro_evaluation, accounting_quality),
    format = "file"
  ),
  tar_target(
    test_files,
    list.files("tests/testthat", pattern = "\\.R$", full.names = TRUE),
    format = "file"
  ),
  tar_target(test_results, { test_files; run_test_suite() }, format = "file")
)
