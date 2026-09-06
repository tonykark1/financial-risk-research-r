-- Period-specific size-peer percentile and z-score ranking.
SELECT CIK, period_end, available_at, kpi, peer_group, value,
       percentile_rank, peer_z_score, peer_median, peer_q1, peer_q3, peer_n
FROM read_parquet('data/gold/fundamentals/peer_kpi_statistics.parquet')
WHERE kpi = 'operating_margin'
ORDER BY CAST(period_end AS DATE) DESC, percentile_rank DESC;

