-- Largest increases in the supplied debt/equity leverage proxy.
WITH leverage AS (
  SELECT CIK, period_end, available_at,
         debt / nullif(equity, 0) AS leverage
  FROM read_parquet('data/gold/fundamentals/company_financials.parquet')
  WHERE NOT future_period_flag
), changes AS (
  SELECT *, leverage - lag(leverage) OVER (
    PARTITION BY CIK ORDER BY CAST(period_end AS DATE), CAST(available_at AS DATE)
  ) AS leverage_change
  FROM leverage
)
SELECT * FROM changes
ORDER BY leverage_change DESC
LIMIT 100;

