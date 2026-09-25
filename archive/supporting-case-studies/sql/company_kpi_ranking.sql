-- Latest ROA ranking, with filing availability retained.
WITH ranked_vintages AS (
  SELECT *, row_number() OVER (
    PARTITION BY CIK, kpi ORDER BY CAST(period_end AS DATE) DESC, CAST(available_at AS DATE) DESC
  ) AS rn
  FROM read_parquet('data/gold/fundamentals/company_kpis.parquet')
  WHERE kpi = 'roa'
)
SELECT CIK, period_end, available_at, value AS roa
FROM ranked_vintages
WHERE rn = 1
ORDER BY roa DESC
LIMIT 100;

