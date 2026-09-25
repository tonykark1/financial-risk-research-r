build_company_kpis <- function(fundamentals, config) {
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  output <- project_path("data/gold/fundamentals/company_kpis.parquet",
    root = config$project_root
  )
  query <- sprintf(paste(
    "WITH facts AS (SELECT *, TRY_CAST(period_end AS DATE) AS period_end_date,",
    "TRY_CAST(available_at AS DATE) AS available_date FROM read_parquet(%s)",
    "WHERE comparison_eligible AND TRY_CAST(period_end AS DATE) <= TRY_CAST(available_at AS DATE)),",
    "flows AS (SELECT CIK, accession, period_end, available_at, period_end_date, available_date,",
    "fact_period_type AS frequency, TRY_CAST(fiscal_year AS INTEGER) AS fiscal_year, fiscal_period,",
    "min(period_start) AS period_start,",
    "CAST(round(median(duration_days)) AS INTEGER) AS duration_days,",
    "median(normalized_value) FILTER (WHERE standardized_concept='revenue') AS revenue,",
    "median(normalized_value) FILTER (WHERE standardized_concept='gross_profit') AS gross_profit,",
    "median(normalized_value) FILTER (WHERE standardized_concept='operating_income') AS operating_income,",
    "median(normalized_value) FILTER (WHERE standardized_concept='net_income') AS net_income,",
    "median(normalized_value) FILTER (WHERE standardized_concept='operating_cash_flow') AS operating_cash_flow,",
    "median(normalized_value) FILTER (WHERE standardized_concept='capex') AS capex,",
    "median(normalized_value) FILTER (WHERE standardized_concept='interest_expense') AS interest_expense",
    "FROM facts WHERE TRY_CAST(fiscal_year AS INTEGER) IS NOT NULL AND ((fact_period_type='quarterly' AND form LIKE '10-Q%%' AND fiscal_period IN ('Q1','Q2','Q3'))",
    "OR (fact_period_type='annual' AND form IN ('10-K','10-K/A','20-F','20-F/A','40-F','40-F/A') AND fiscal_period='FY'))",
    "GROUP BY CIK, accession, period_end, available_at, period_end_date, available_date, fact_period_type,",
    "TRY_CAST(fiscal_year AS INTEGER), fiscal_period),",
    "balances AS (SELECT CIK, accession, period_end, available_at,",
    "median(normalized_value) FILTER (WHERE standardized_concept='assets') AS assets,",
    "median(normalized_value) FILTER (WHERE standardized_concept='liabilities') AS liabilities,",
    "median(normalized_value) FILTER (WHERE standardized_concept='equity') AS equity,",
    "median(normalized_value) FILTER (WHERE standardized_concept='cash') AS cash,",
    "median(normalized_value) FILTER (WHERE standardized_concept='debt') AS debt",
    "FROM facts WHERE fact_period_type='instant' GROUP BY CIK, accession, period_end, available_at),",
    "panels AS (SELECT f.*, b.assets, b.liabilities, b.equity, b.cash, b.debt",
    "FROM flows f LEFT JOIN balances b USING (CIK, accession, period_end, available_at)),",
    "initial_panels AS (SELECT * FROM panels QUALIFY row_number() OVER (",
    "PARTITION BY CIK,frequency,fiscal_year,fiscal_period ORDER BY available_date,accession)=1),",
    "with_prior_raw AS (SELECT *, lag(period_end_date) OVER w AS prior_period,",
    "lag(fiscal_year) OVER w AS prior_fiscal_year, lag(fiscal_period) OVER w AS prior_fiscal_period,",
    "lag(revenue) OVER w AS prior_revenue, lag(assets) OVER w AS prior_assets, lag(equity) OVER w AS prior_equity,",
    "lag(operating_income) OVER w AS prior_operating_income,",
    "lag(operating_cash_flow) OVER w AS prior_operating_cash_flow,",
    "lag(interest_expense) OVER w AS prior_interest_expense, lag(debt) OVER w AS prior_debt",
    "FROM initial_panels WINDOW w AS (PARTITION BY CIK,frequency ORDER BY fiscal_year,",
    "CASE fiscal_period WHEN 'Q1' THEN 1 WHEN 'Q2' THEN 2 WHEN 'Q3' THEN 3 ELSE 4 END)),",
    "with_prior AS (SELECT *, CASE WHEN frequency='annual' THEN prior_fiscal_year=fiscal_year-1",
    "WHEN frequency='quarterly' AND fiscal_period='Q2' THEN prior_fiscal_year=fiscal_year AND prior_fiscal_period='Q1'",
    "WHEN frequency='quarterly' AND fiscal_period='Q3' THEN prior_fiscal_year=fiscal_year AND prior_fiscal_period='Q2'",
    "ELSE false END AS prior_comparable FROM with_prior_raw),",
    "calculated AS (SELECT *, CASE WHEN prior_comparable THEN revenue/nullif(prior_revenue,0)-1 END AS revenue_growth,",
    "gross_profit/nullif(revenue,0) AS gross_margin, operating_income/nullif(revenue,0) AS operating_margin,",
    "CASE WHEN prior_comparable THEN net_income/nullif((assets+prior_assets)/2,0) END AS roa,",
    "CASE WHEN prior_comparable THEN net_income/nullif((equity+prior_equity)/2,0) END AS roe,",
    "operating_income/nullif(assets-cash,0) AS roic_proxy,",
    "CASE WHEN prior_comparable THEN revenue/nullif((assets+prior_assets)/2,0) END AS asset_turnover,",
    "debt-cash AS net_debt, (debt-cash)/nullif(operating_income,0) AS net_debt_to_operating_income_proxy,",
    "debt/nullif(equity,0) AS debt_to_equity, operating_income/nullif(interest_expense,0) AS interest_coverage,",
    "operating_cash_flow/nullif(revenue,0) AS cfo_margin, operating_cash_flow-capex AS fcf,",
    "(operating_cash_flow-capex)/nullif(revenue,0) AS fcf_margin, capex/nullif(revenue,0) AS capex_intensity,",
    "CASE WHEN prior_comparable THEN (net_income-operating_cash_flow)/nullif((assets+prior_assets)/2,0) END AS accrual_ratio,",
    "operating_cash_flow/nullif(net_income,0) AS cash_conversion,",
    "CASE WHEN prior_comparable THEN operating_income/nullif(revenue,0)-prior_operating_income/nullif(prior_revenue,0) END AS operating_margin_change,",
    "CASE WHEN prior_comparable THEN operating_cash_flow/nullif(revenue,0)-prior_operating_cash_flow/nullif(prior_revenue,0) END AS cfo_margin_change,",
    "CASE WHEN prior_comparable THEN debt/nullif(equity,0)-prior_debt/nullif(prior_equity,0) END AS debt_to_equity_change,",
    "CASE WHEN prior_comparable THEN operating_income/nullif(interest_expense,0)-prior_operating_income/nullif(prior_interest_expense,0) END AS interest_coverage_change",
    "FROM with_prior)",
    "SELECT CIK, period_start, period_end, available_at, accession, frequency, fiscal_year, fiscal_period, duration_days,",
    "'direct_reported_duration_first_vintage' AS normalization_method, kpi, value",
    "FROM calculated, LATERAL (VALUES",
    "('revenue_growth',revenue_growth),('gross_margin',gross_margin),('operating_margin',operating_margin),",
    "('roa',roa),('roe',roe),('roic_proxy',roic_proxy),('asset_turnover',asset_turnover),",
    "('net_debt',net_debt),('net_debt_to_operating_income_proxy',net_debt_to_operating_income_proxy),",
    "('debt_to_equity',debt_to_equity),('interest_coverage',interest_coverage),('cfo_margin',cfo_margin),",
    "('fcf',fcf),('fcf_margin',fcf_margin),('capex_intensity',capex_intensity),",
    "('accrual_ratio',accrual_ratio),('cash_conversion',cash_conversion),",
    "('operating_margin_change',operating_margin_change),('cfo_margin_change',cfo_margin_change),",
    "('debt_to_equity_change',debt_to_equity_change),('interest_coverage_change',interest_coverage_change)",
    ") AS metrics(kpi,value) WHERE value IS NOT NULL AND isfinite(value)"
  ), sql_path(fundamentals$normalized_facts_path))
  copy_query_to_parquet(con, query, output)
  formulae <- data.table::data.table(
    kpi = c("revenue_growth", "gross_margin", "operating_margin", "roa", "roe",
      "roic_proxy", "asset_turnover", "net_debt", "net_debt_to_operating_income_proxy",
      "debt_to_equity", "interest_coverage", "cfo_margin", "fcf", "fcf_margin", "capex_intensity",
      "accrual_ratio", "cash_conversion", "operating_margin_change", "cfo_margin_change",
      "debt_to_equity_change", "interest_coverage_change"),
    formula = c(
      "revenue / prior-period revenue - 1", "gross profit / revenue",
      "operating income / revenue", "net income / average assets",
      "net income / average equity", "operating income / (assets - cash)",
      "revenue / average assets", "debt - cash", "(debt - cash) / operating income proxy",
      "debt / equity", "operating income / interest expense", "operating cash flow / revenue",
      "operating cash flow - capex", "FCF / revenue", "capex / revenue",
      "(net income - operating cash flow) / average assets", "operating cash flow / net income",
      "current operating margin - PIT-compatible prior-period margin",
      "current CFO margin - PIT-compatible prior-period CFO margin",
      "current debt/equity - PIT-compatible prior-period debt/equity",
      "current interest coverage - PIT-compatible prior-period interest coverage"
    ),
    caveat = rep(paste(
      "Quarterly and annual facts are calculated separately from direct reported durations;",
      "YTD and ambiguous contexts are excluded. KPIs use the first filed vintage for each fiscal period;",
      "later restatements remain preserved in the normalized fact mart.",
      "Zero denominators return missing."
    ), 21)
  )
  writeLines(c("# KPI formulae", "", write_markdown_table(formulae)),
    "docs/kpi_formulae.md", useBytes = TRUE
  )
  list(kpis_path = output, formulae = formulae)
}

build_company_anomalies <- function(kpis, config) {
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  output <- project_path("data/gold/fundamentals/company_anomalies.parquet",
    root = config$project_root
  )
  query <- sprintf(paste(
    "WITH x AS (SELECT CIK, period_end, available_at, accession, frequency,",
    "max(value) FILTER (WHERE kpi='revenue_growth') AS revenue_growth,",
    "max(value) FILTER (WHERE kpi='cfo_margin_change') AS cfo_margin_change,",
    "max(value) FILTER (WHERE kpi='operating_margin_change') AS operating_margin_change,",
    "max(value) FILTER (WHERE kpi='debt_to_equity') AS debt_to_equity,",
    "max(value) FILTER (WHERE kpi='debt_to_equity_change') AS debt_to_equity_change,",
    "max(value) FILTER (WHERE kpi='interest_coverage') AS interest_coverage,",
    "max(value) FILTER (WHERE kpi='interest_coverage_change') AS interest_coverage_change,",
    "max(value) FILTER (WHERE kpi='accrual_ratio') AS accrual_ratio",
    "FROM read_parquet(%s) GROUP BY CIK,period_end,available_at,accession,frequency)",
    "SELECT CIK, period_end, available_at, accession, frequency,",
    "coalesce(revenue_growth < -0.2,false) AS revenue_down_sharply,",
    "false AS receivables_rising_faster_than_sales, false AS inventory_rising_faster_than_sales,",
    "coalesce(cfo_margin_change < -0.1,false) AS cfo_deterioration,",
    "coalesce(operating_margin_change < -0.1,false) AS margin_collapse,",
    "coalesce(debt_to_equity > 1.5 AND debt_to_equity_change > 0.5,false) AS leverage_spike,",
    "coalesce(interest_coverage < 1 AND interest_coverage_change < -1,false) AS interest_coverage_collapse,",
    "coalesce(abs(accrual_ratio) > 0.1,false) AS unusual_accruals,",
    "true AS unavailable_working_capital_flag",
    "FROM x"
  ), sql_path(kpis$kpis_path))
  copy_query_to_parquet(con, query, output)
  output
}
