render_fundamentals_reports <- function(fundamentals, accounting_quality, kpis, anomalies_path,
                                        peers, config) {
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  coverage <- data.table::as.data.table(DBI::dbGetQuery(con, sprintf(paste(
    "SELECT COUNT(*) AS kpi_records, COUNT(DISTINCT CIK) AS companies,",
    "COUNT(DISTINCT kpi) AS kpis, MIN(period_end) AS start_period, MAX(period_end) AS end_period,",
    "SUM(CAST(frequency='quarterly' AS INTEGER)) AS quarterly_records,",
    "SUM(CAST(frequency='annual' AS INTEGER)) AS annual_records",
    "FROM read_parquet(%s)"
  ), sql_path(kpis$kpis_path))))
  anomaly_summary <- data.table::as.data.table(DBI::dbGetQuery(con, sprintf(paste(
    "SELECT COUNT(*) AS records,",
    "SUM(CAST(revenue_down_sharply AS INTEGER)) AS revenue_down_sharply,",
    "SUM(CAST(cfo_deterioration AS INTEGER)) AS cfo_deterioration,",
    "SUM(CAST(margin_collapse AS INTEGER)) AS margin_collapse,",
    "SUM(CAST(leverage_spike AS INTEGER)) AS leverage_spike,",
    "SUM(CAST(interest_coverage_collapse AS INTEGER)) AS interest_coverage_collapse,",
    "SUM(CAST(unusual_accruals AS INTEGER)) AS unusual_accruals",
    "FROM read_parquet(%s)"
  ), sql_path(anomalies_path))))
  top_deterioration <- data.table::as.data.table(DBI::dbGetQuery(con, sprintf(paste(
    "SELECT CIK, period_end, frequency, value AS revenue_growth FROM read_parquet(%s)",
    "WHERE kpi='revenue_growth' ORDER BY value ASC LIMIT 50"
  ), sql_path(kpis$kpis_path))))
  summary <- paste(
    "SEC filing vintages are retained by CIK, accession, period end, and availability date.",
    "Direct-quarter and annual flow facts are calculated separately from their reported durations;",
    "YTD and ambiguous contexts are excluded from comparable KPIs. Historical KPI comparisons use",
    "the first filed vintage for each fiscal period; later restatements remain preserved in the normalized fact mart.",
    "Ratios use guarded denominators and no source vintage is overwritten."
  )
  dashboard <- write_quarto_report("Automated Financial Data & KPI Pipeline", summary,
    list("Coverage" = coverage, "KPI formulae" = kpis$formulae,
      "Largest reported revenue deteriorations" = top_deterioration),
    "reports/fundamentals/company_kpi_dashboard.qmd", config
  )
  quality <- write_quarto_report("Fundamentals Data Quality Report", summary,
    list("Accounting and vintage checks" = accounting_quality$summary,
      "Transparent anomaly counts" = anomaly_summary,
      "Field coverage" = fundamentals$dictionary,
      "Duration-normalization rules" = data.table::data.table(
        class = c("Instant", "Quarterly", "Annual", "YTD / ambiguous"),
        rule = c("Balance-sheet concept or instant context", "70-110 days", "330-380 days", "111-329 days / outside thresholds"),
        comparable_KPI_use = c("Joined to same filing", "Yes - quarterly only", "Yes - annual only", "No")
      )),
    "reports/fundamentals/data_quality_report.qmd", config
  )
  peer_report <- write_quarto_report("Fundamentals Size-Cohort Analysis",
    "Cohorts use period-specific asset-size deciles because sector, industry, and country are not available in the supplied normalized mart. They are not industry peers, and this limitation is explicit in every cohort-map row.",
    list("Coverage" = coverage), "reports/fundamentals/peer_analysis.qmd", config
  )
  c(dashboard, quality, peer_report)
}
