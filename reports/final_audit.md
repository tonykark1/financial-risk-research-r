# Skeptical final audit

## Evidence that is strong

- Raw sources remain immutable and large reads are database-backed.
- Point-in-time, filing-vintage, rolling-window, and chronological-split tests pass.
- Bank and macro model results are genuinely out of sample; weak results are retained.
- SEC accounting anomalies and malformed dates are explicit flags.
- Reports are rendered from executed outputs and metrics are machine-generated.

## Remaining weaknesses

1. Bank credit, market, and country-macro risk dimensions remain incomplete because the supplied upstream marts are empty or lack verified bank-security links.
2. Bank availability dates use a conservative 120-day estimate; exact EBA publication calendars should replace it.
3. Bank modelling has only 16 periods, which limits crisis/regime stratification and makes complex models fragile.
4. Macro realized variance uses daily returns rather than intraday data.
5. True vintages exist for only a controlled subset of macro series.
6. Comparable quarterly SEC KPIs use direct Q1-Q3 10-Q facts; fiscal Q4 is not derived from annual-minus-Q1-Q3 because that requires additional cross-concept validation.
7. Fundamentals peers are size-only pending sector, industry, and country metadata.
8. The full pipeline requires the supplied local lake; only the deterministic demo is portable in CI.

## Trust decision

A risk analyst can trust the explicit capital/profitability bank ranking and flags, but should not treat missing dimensions as evidence of low risk. A quant researcher can reproduce the chronological macro comparison and inspect its DM tests. A data engineer can rebuild the compact outputs without copying the raw lake. An interviewer can reproduce the reports with `renv::restore()` and `targets::tar_make()`.

## Reproducible metric snapshot



|metric                             |value      |
|:----------------------------------|:----------|
|Banks                              |144        |
|Countries                          |28         |
|Bank-quarter observations          |1893       |
|Bank panel start                   |2020-09-30 |
|Bank panel end                     |2024-06-30 |
|LEI mapping rate                   |1          |
|Bank ticker mapping rate           |0          |
|Macro series used                  |10         |
|Vintage-enabled macro series used  |10         |
|Market instruments                 |38         |
|SEC filing issuers                 |51311      |
|SEC filings                        |3212976    |
|Upstream XBRL facts exposed        |124727683  |
|Selected facts duration-normalized |11050014   |
|Comparable KPI companies           |15752      |
|Comparable KPI records transformed |2162632    |
|Model-horizon experiments          |28         |
|Forecast observations              |127218     |
|Automated tests                    |17         |
