-- Four-observation rolling KPI mean; period duration caveat is documented in docs/kpi_formulae.md.
SELECT CIK, period_end, available_at, kpi, value,
       avg(value) OVER (
         PARTITION BY CIK, kpi ORDER BY CAST(period_end AS DATE), CAST(available_at AS DATE)
         ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
       ) AS rolling_4_observation_mean
FROM read_parquet('data/gold/fundamentals/company_kpis.parquet');

