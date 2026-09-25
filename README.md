# Point-in-Time Volatility Research

**Research question:** Does information genuinely available at forecast time improve equity-index volatility forecasts beyond a parsimonious HAR baseline?

The corrected experiment has a split result: **Elastic Net had the lowest sample-average out-of-sample QLIKE at 1 and 5 days, while HAR plus VIX led at 10 and 22 days.** Neither tested tree ensemble led at any horizon under the implemented tuning and retraining protocol. These are sample- and metric-specific rankings, not a general claim that nonlinear models cannot help.

![Forecast loss relative to HAR](figures/benchmark-relative-qlike.png)

## Results in one minute

| Horizon | Lowest-QLIKE model | Forecast records | QLIKE | Variance RMSE |
|---:|:---|---:|---:|---:|
| 1 day | Elastic Net | 4,552 | -6.582416 | 0.000564 |
| 5 days | Elastic Net | 4,548 | -6.681832 | 0.001909 |
| 10 days | HAR + VIX | 4,543 | -5.916593 | 0.003007 |
| 22 days | HAR + VIX | 4,531 | -4.946431 | 0.006556 |
At 10 days, HAR plus VIX and Elastic Net are nearly tied on average QLIKE; no direct pairwise significance claim is made between them.


The experiment generated **127,218 model forecasts**:

```text
7 models × (4,552 + 4,548 + 4,543 + 4,531 forecast dates)
= 7 × 18,174 date–horizon evaluations
= 127,218 model–date–horizon predictions
```

This is not 127,218 independent market events: models share forecast origins, horizons reuse dates, and multi-day targets overlap. The largest panel contains 4,552 unique forecast dates.

Read the [focused research report](report/analysis.md), inspect the [saved model metrics](results/model_metrics.csv), or browse the [ten diagnostic figures](figures/macro_gallery/).

## Data and target

The target is future variance over 1, 5, 10, or 22 trading days, constructed from subsequent S&P 500 close-to-close daily returns. This is a **daily variance proxy**, not intraday realized volatility.

Inputs include:

- HAR daily, weekly, and monthly volatility components;
- market VIX;
- release-dated federal funds, Treasury-yield, credit-spread, unemployment, CPI, industrial-production, and real-GDP series.

Market history is retrieval-time data. The macro-release panel retains observation and recorded availability dates, and as-of joins exclude records dated after each forecast origin. Same-day HAR and market-VIX inputs use an after-close convention. The full source lake is private and is not committed; compact result snapshots and a deterministic fixture are public.

## Models

Seven specifications are evaluated at each horizon:

1. HAR
2. HAR + VIX
3. HAR + rates
4. Ridge
5. Elastic Net
6. Random Forest
7. XGBoost

Ridge, Elastic Net, Random Forest, and XGBoost use small predefined searches on a chronological validation tail. Selection uses log-variance mean squared error; final ranking uses QLIKE. Linear and regularised models retrain every 22 trading days, while the tree models retrain every 66 days. The negative complexity result therefore applies to these implemented protocols—it is not a universal claim about machine learning.

**Method revision (September 2026):** an audit corrected the mapping between `glmnet` validation-loss columns and candidate penalties. Every committed result artifact in this release was regenerated after that correction.

## Evaluation protocol

- Forecasting begins after a 756-row history; target-availability gating leaves slightly fewer eligible training observations at longer horizons.
- Release-dated macro features enter only when recorded as available; same-day HAR and market-VIX inputs follow the after-close convention.
- A forward target enters training only after its complete horizon has elapsed.
- Test observations never enter imputation, scaling, tuning, or fitting.
- Overlapping-horizon Diebold–Mariano comparisons use Newey-West/HAC inference.
- Fitting errors are retained as missing row-level predictions; this execution's failure count is published in the headline metadata. Underperforming specifications remain visible in the metrics.

Preprocessing is fitted on the full outer training window before its final 20% is used for hyperparameter selection. This does not leak the test set, but it is not strictly nested with respect to the tuning holdout.

## Five-minute deterministic demo

The demo needs no private source lake. It checks chronological splitting, target-availability gating, and a HAR versus HAR + VIX comparison on a deterministic fixture:

```text
Rscript scripts/run_demo.R
```

Output: `demo/output/macro_demo.html` and `demo/output/runtime.json`.

The demo verifies workflow mechanics. It does not reproduce the full 127,218-forecast experiment.

## Full reproduction

```r
renv::restore()
Sys.setenv(FINANCIAL_RESEARCH_UPSTREAM_ROOT = "path/to/source-lake")
targets::tar_make()
testthat::test_dir("tests/testthat")
```

The full run reads Parquet/DuckDB inputs from the local source lake without modifying them and writes compact results, figures, and the report. Without that lake, a fresh clone can reproduce the demo and tests, but not the headline numerical experiment.

## Limitations

- Close-to-close squared returns are a noisy volatility proxy; they are not an intraday realized measure.
- The evidence covers one index and forecast dates from 3 July 2008 through 7 August 2026; other indices and periods are untested.
- HAR + VIX uses retrieval-time market VIX; availability-date controls apply to the macro-release panel.
- Hyperparameter searches are deliberately narrow and optimise log-MSE rather than QLIKE.
- Models are fitted to log variance and exponentiated for level metrics without a separate smearing correction.
- Tree models use a less frequent retraining schedule than the other models.
- Nominal DM p-values are not adjusted for the full family of 24 comparisons; the 22-day HAR + VIX comparison is borderline at `p = 0.0497`.
- No trading positions, turnover, transaction costs, or strategy returns are modelled. These results do **not** establish trading profitability.

## Repository map

```text
R/macro_vol/          data preparation, walk-forward models, evaluation, figures
data/demo/input/      deterministic public fixture
figures/macro_gallery committed diagnostic figures
report/analysis.md    focused research report
results/              auditable result snapshots
scripts/run_demo.R    portable five-minute entry point
tests/testthat/       timing, leakage, calculation, and result-contract tests
archive/              preserved material from the earlier multi-project version
```

The previous bank-risk and SEC-fundamentals case studies were preserved under [`archive/`](archive/) and are outside this release's active pipeline.

