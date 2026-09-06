-- Filing-aware lagged KPI comparison.
SELECT CIK, period_end, available_at, kpi, value,
       lag(value) OVER (PARTITION BY CIK, kpi ORDER BY CAST(period_end AS DATE), CAST(available_at AS DATE)) AS prior_value,
       value - lag(value) OVER (PARTITION BY CIK, kpi ORDER BY CAST(period_end AS DATE), CAST(available_at AS DATE)) AS change
FROM read_parquet('data/gold/fundamentals/company_kpis.parquet');

