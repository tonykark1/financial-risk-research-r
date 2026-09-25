# Repository audit

Audit date: 2026-08-13  
Upstream repository: external read-only source lake (configured with `FINANCIAL_RESEARCH_UPSTREAM_ROOT`)

## Executive assessment

The upstream repository is an executed Python data lake rather than an R research project. It is a strong immutable source layer: 670 files occupy 7.864 GB, including 278 Parquet files (2.954 GB), 18 ZIP archives (3.285 GB), 87 CSV files (1.371 GB), 88 Excel workbooks, 92 JSON files, and a 274 KB DuckDB catalogue database. It already contains raw, bronze, silver, and gold data for EBA, SEC, GLEIF, ESMA, macro, market, factor, and fund-holdings sources.

The main research gap is not data acquisition. It is the absence of the requested R orchestration, modelling, validation, reporting, and portfolio-facing evidence. Several nominal gold outputs are empty, and the upstream bank panel is observation-level rather than a defensible one-row-per-bank-quarter modelling panel.

This R project therefore treats the upstream lake as read-only and creates only filtered analytical tables, model outputs, reports, figures, tests, and a local DuckDB database.

## Repository structure found

| Area | Files | Approx. size | Assessment |
|---|---:|---:|---|
| `data/` | 546 | 7.360 GB | Primary immutable data layer |
| `catalog/` | 19 | 0.467 GB | Existing inventories and entity/identifier tables |
| `src/` | 65 | <1 MB | Python ingestion, normalization, marts, validation, reports |
| `reports/` | 6 | <1 MB | Coverage and limitations only; not the three research reports |
| `tests/` | 6 | <1 MB | Small Python smoke-test suite |
| `database/` | 1 | 0.0003 GB | DuckDB views over Parquet |
| `.vendor/` | packaged Python dependencies | 0.035 GB | Not reused by the R workflow |

No R project, `_targets.R`, `renv.lock`, Quarto research reports, R tests, or executed predictive-model outputs were present.

## Dataset inventory

The upstream catalogue reports the following material gold datasets.

| Dataset | Reported rows | PIT/vintage support | Notes |
|---|---:|---|---|
| Bank quarterly panel | 4,838,767 | partial | Too many rows for one bank-quarter; requires aggregation and schema validation |
| Bank credit exposures | 5,087,759 | source-file vintage | Granular EBA exposure records |
| Bank sovereign exposures | 1,648,127 | source-file vintage | Granular EBA sovereign records |
| Bank stress tests | 2,516,636 | exercise vintage | 2023 and 2025 exercises in current lake |
| Macro vintages | 97,506 | mixed | True ALFRED vintages for selected high-volume FRED series; current-revised sources flagged |
| Market daily | 263,216 | retrieval-time only | 38 instruments, 1970-2026; Yahoo fallback limitations documented |
| Realized volatility | 32,261 | derived | Existing daily/forward volatility fields require leakage audit |
| SEC selected fundamentals | 12,179,501 | filing vintage | Provenance-preserving selected facts |
| SEC wide fundamentals | 2,016,620 | filing vintage | Wide normalized observations |
| Company KPIs | 5,219,766 | filing vintage | Existing KPIs require formula and denominator QA |
| Filing metadata | 3,212,976 | filing date/acceptance where available | 51,311 CIKs according to upstream README |
| Entity master | 3,398,022 | current/historical GLEIF fields | 145 EBA LEIs reportedly mapped |
| Instrument reference | 823,882 | retrieval snapshot | Current bounded ESMA FIRDS subset |

Empty or effectively empty outputs were found for `bank_macro_panel`, `bank_market_daily`, `predictor_panel`, `company_peer_map`, `macro_regimes`, and `sanctions_reference`. These names must not be treated as completed deliverables.

## Raw and processed source coverage

- EBA transparency exercises for 2021-2024 and stress tests for 2023 and 2025, plus 76 risk-dashboard workbooks spanning 2014-2026.
- SEC official `companyfacts.zip` (1.401 GB) and `submissions.zip` (1.557 GB), with partitioned silver facts.
- GLEIF LEI Golden Copy, relationship records, and ISIN-LEI mapping.
- FRED/ALFRED, ECB, and Eurostat macro observations; only some series have true revision histories.
- Yahoo market data fallback, Fama-French factor archives, and current iShares holdings snapshots.
- Current bounded ESMA FIRDS/FITRS files, not a full historical regulatory mirror.

## Data quality evidence and risks

- The upstream quality report flags 4,188,677 duplicate keys in `eba_bank_observations`; these may be legitimate native dimensions but prove the data are not yet a bank-quarter panel.
- Macro observations contain 2,261 missing values.
- One duplicate fund-holding key is flagged.
- EBA schemas and participating-bank populations change across exercises.
- SEC concepts, units, taxonomy extensions, amendments, and restatements require vintage-preserving selection.
- Market history relies on an unofficial Yahoo fallback and can contain survivorship, delisting, ticker-change, and corporate-action limitations.
- Current-revised ECB/Eurostat observations cannot be backdated as historical information sets.
- Several upstream paths exist with zero rows; existence of a Parquet file is not evidence of usable coverage.

## Duplicate and stale datasets

- `catalog/entity_master.parquet` and `data/gold/regulatory/entity_master.parquet` have identical byte size and appear duplicated; checksums will be recorded by the executable inventory.
- Transparency 2024 bronze files appear under both canonical and `tr_*` names, suggesting duplicated representations that need checksum/schema comparison.
- Raw downloads are timestamped 2026-08-10 and are internally consistent with the upstream README. They are not stale for the supplied snapshot, but should not be described as live data after that date.
- The current ESMA subset and current ETF holdings are snapshots, not historical panels.

## Existing code worth reusing conceptually

- Provenance and source path conventions from the Python lake.
- The distinction between `observation_period` and `available_at`.
- Deterministic SEC concept precedence and preservation of native concepts.
- Existing DuckDB view naming and partitioned SEC storage.

The R implementation will not call Python modules during normal operation.

## Existing outputs worth preserving

- Upstream gold Parquet marts and catalogues.
- Upstream coverage, limitations, and unavailable-source reports.
- Raw retrieval timestamps, checksums, filing accessions, and source paths.

## Missing expected deliverables

- R project foundation, `targets` pipeline, `renv.lock`, R tests, and structured R logs.
- A validated entity crosswalk with ambiguity reporting in the requested output location.
- Reusable point-in-time joins with automated no-future-information tests.
- Executed bank risk scores, targets, time-based models, stress scenarios, and reports.
- Executed macro HAR/ML walk-forward forecasts, QLIKE/DM tests, regime analysis, and reports.
- Executed accounting QA, anomaly flags, peer analytics, SQL examples, and fundamentals reports.
- `reports/cv_metrics.md` and `reports/interview_notes.md` populated only from executed outputs.

## Audit decision

No large source will be re-downloaded or copied. The R workflow will query upstream Parquet directly through DuckDB, persist only compact gold/model/report outputs locally, and retain explicit availability and provenance fields throughout.


