-- Largest revenue deterioration observations.
SELECT CIK, period_end, available_at, value AS revenue_growth
FROM read_parquet('data/gold/fundamentals/company_kpis.parquet')
WHERE kpi = 'revenue_growth'
ORDER BY revenue_growth ASC
LIMIT 100;

