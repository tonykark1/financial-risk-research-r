build_peer_analysis <- function(fundamentals, kpis, config) {
  con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  map_path <- project_path("data/gold/fundamentals/company_peer_map.parquet",
    root = config$project_root
  )
  map_query <- sprintf(paste(
    "WITH ranked AS (SELECT CIK, period_end, available_at, assets,",
    "row_number() OVER (PARTITION BY CIK, period_end ORDER BY available_at DESC) AS rn",
    "FROM read_parquet(%s) WHERE NOT future_period_flag AND assets > 0),",
    "latest AS (SELECT * FROM ranked WHERE rn=1)",
    "SELECT CIK, period_end, concat('size_decile_',",
    "ntile(10) OVER (PARTITION BY period_end ORDER BY assets)) AS peer_group,",
    "assets AS peer_size_basis, 'size-only; sector/country unavailable' AS mapping_method",
    "FROM latest"
  ), sql_path(fundamentals$financials_path))
  copy_query_to_parquet(con, map_query, map_path)
  peer_path <- project_path("data/gold/fundamentals/peer_kpi_statistics.parquet",
    root = config$project_root
  )
  peer_query <- sprintf(paste(
    "WITH joined AS (SELECT k.*, p.peer_group FROM read_parquet(%s) k",
    "JOIN read_parquet(%s) p USING (CIK, period_end)),",
    "stats AS (SELECT *, count(*) OVER g AS peer_n, avg(value) OVER g AS peer_mean,",
    "stddev_samp(value) OVER g AS peer_sd, median(value) OVER g AS peer_median,",
    "quantile_cont(value,0.25) OVER g AS peer_q1, quantile_cont(value,0.75) OVER g AS peer_q3,",
    "percent_rank() OVER (PARTITION BY period_end,frequency,kpi,peer_group ORDER BY value) AS percentile_rank",
    "FROM joined WINDOW g AS (PARTITION BY period_end,frequency,kpi,peer_group))",
    "SELECT *, (value-peer_mean)/nullif(peer_sd,0) AS peer_z_score FROM stats WHERE peer_n >= %d"
  ), sql_path(kpis$kpis_path), sql_path(map_path), config$fundamentals$peer_minimum_n)
  copy_query_to_parquet(con, peer_query, peer_path)
  list(peer_map_path = map_path, peer_statistics_path = peer_path)
}
