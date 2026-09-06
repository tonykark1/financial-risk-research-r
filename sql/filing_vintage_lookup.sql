-- Replace the CIK and as-of date to reproduce the information set visible on that date.
WITH eligible AS (
  SELECT *, row_number() OVER (
    PARTITION BY CIK, period_end ORDER BY CAST(available_at AS TIMESTAMP) DESC
  ) AS vintage_rank
  FROM read_parquet('data/gold/fundamentals/company_financials.parquet')
  WHERE CIK = '0000320193'
    AND CAST(available_at AS DATE) <= DATE '2024-03-01'
)
SELECT * FROM eligible
WHERE vintage_rank = 1
ORDER BY CAST(period_end AS DATE) DESC;

