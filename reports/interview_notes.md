# Interview defense notes

## European Bank Capital & Profitability Monitor

- **Research question:** Which EBA banks warrant monitoring based on supported capital and profitability indicators?
- **Why it matters:** It converts granular, changing EBA disclosures into a bank-period monitoring and validation workflow.
- **Data:** 144 LEIs, 16 reporting periods, EBA transparency data, deterministic GLEIF/ISIN mappings, and vintage-aware macro history.
- **Key design choice:** Preserve raw anomalies, create model-ready copies only after flags, and score only supported dimensions.
- **Strongest result:** Lowest RMSE by horizon: Ridge@1, Elastic_Net@2, Elastic_Net@4.
- **Weakest result:** Every fitted CET1-deterioration model has negative out-of-sample R-squared versus the zero-change persistence benchmark.
- **Major limitation:** The supplied data do not support defensible bank-equity, credit, or country-macro dimensions; the component is not a comprehensive bank-risk model.
- **Timing status:** Conservative pseudo-PIT using quarter end plus 120 days; exact EBA publication timestamps are absent.
- **Look-ahead safeguards:** A training row enters only after its forward target quarter is earlier than the forecast quarter.
- **Why simple baselines:** Persistence is economically natural for regulatory capital and proved difficult to beat.
- **What failed:** Complexity did not add robust OOS signal; this is reported rather than hidden.
- **Improvement:** Add verified bank-security mappings, richer quarterly EBA variables, and an authoritative publication calendar.

## Real-Time Macro / Volatility Forecasting

- **Research question:** Does macro information genuinely available at forecast time improve volatility forecasts beyond HAR?
- **Data:** S&P 500 daily returns/realized-variance proxies, VIX, rates, curve, spreads, inflation, labor, activity, and GDP true vintages where available.
- **Key design choice:** Exclude current-revised macro history from historical forecasts and gate target availability for overlapping horizons.
- **Strongest result:** Best QLIKE model by horizon: HAR_VIX@1, HAR_VIX@5, HAR_VIX@10, HAR_VIX@22.
- **Weakest result:** Tree ensembles trail HAR-VIX on QLIKE despite tuning.
- **Major limitation:** Daily realized variance is constructed from close-to-close returns, not intraday returns.
- **Look-ahead safeguards:** Expanding windows; training-only scaling, imputation, tuning; true `available_at`; overlapping-horizon HAC DM tests.
- **Why HAR:** It is parsimonious, interpretable, and a strong volatility baseline.
- **What failed:** Additional complexity did not dominate the compact VIX-augmented HAR specification.
- **Improvement:** Add verified intraday realized measures and a broader true-vintage macro set.

## Automated Financial Data & KPI Pipeline

- **Research question:** Can SEC filing facts become a reproducible, vintage-aware analysis database?
- **Data:** SEC company facts, filing metadata, normalized selected concepts, and every observed filing vintage.
- **Key design choice:** Never overwrite restatements; preserve raw taxonomy/concept/unit/accession upstream and select vintages by availability date.
- **Strongest result:** Executed accounting QA identified 71677 identity breaks and 18 future-period anomalies.
- **Weakest result:** Receivables, inventory, payable, shares, and EPS are absent from the supplied normalized wide mart and are not fabricated.
- **Major limitation:** Size-only peers are used because sector, industry, and country fields are unavailable in the supplied normalized company mart.
- **Look-ahead safeguards:** Filing vintages are selected only when `available_at <= as_of_date`; amendments remain separate.
- **What failed:** The upstream data report zero amendment flags despite evident restatement vintages, so restatements are detected from value changes rather than that flag.
- **Duration policy:** Direct-quarter and annual flows are separated; YTD/ambiguous contexts are excluded; comparable KPI history uses first-filed vintages.
- **Improvement:** Add SIC/NAICS and issuer-country metadata, derive fiscal Q4 only with validated annual-minus-Q1-Q3 logic, and add missing working-capital concepts.

## Likely technical interview questions

1. Why is target availability different from feature availability for a 22-day volatility horizon?
2. How does the rolling as-of join resolve multiple vintages?
3. Why can QLIKE be negative and still be compared correctly?
4. Why use HAC inference for overlapping forecast horizons?
5. Why did the bank models fail to beat persistence?
6. How are implausible EBA ratios handled without silently deleting observations?
7. How do you prevent a restated SEC fact from contaminating historical analysis?
8. What accounting assumptions make the ROIC and net-debt/EBITDA fields proxies?
9. What would justify replacing size-only peers?
10. Which model-complexity additions did you reject, and why?
