# Cashflow transformations

This dbt project defaults to synthetic Plaid-shaped seeds. The explicit `prod`
target reads private S3 batches using temporary transform-role credentials.
Neither target reads Secrets Manager.

## Run locally

From the repository root in Git Bash:

```bash
uv sync
cd transform
uv run dbt build --profiles-dir .
```

Override the ignored local DuckDB location when needed:

```bash
export CASHFLOW_DUCKDB_PATH="../.local/custom.duckdb"
uv run dbt build --profiles-dir .
```

## Run against private S3 data

The `prod` target reads only `s3://cashflow-dashboard/raw/plaid/` using
short-lived credentials from the `cashflow-transform` profile. It writes the
private local database to `.local/cashflow-prod.duckdb`, which is ignored by
Git.

From Git Bash:

```bash
cd ~/Documents/cashflow/transform

eval "$(
  aws configure export-credentials \
    --profile cashflow-transform \
    --format env
)"

uv run dbt build \
  --profiles-dir . \
  --target prod

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_CREDENTIAL_EXPIRATION
```

Run this only in a private development environment. Do not inspect or paste
transaction rows into issues, logs, documentation, or chat.

## Current model boundary

- `stg_plaid_accounts` normalizes non-sensitive account metadata.
- `stg_plaid_transactions` converts Plaid's positive-outflow convention to the
  canonical cashflow sign, excludes pending rows, and deduplicates by Plaid
  transaction ID.
- `fct_transactions` is the canonical transaction fact model and classifies
  income, expenses, refunds, transfers, and card payments.
- Production-only intermediate models replay immutable Plaid add, modify, and
  remove events and derive masked account labels from sanitized raw metadata.

## Classification and monthly metrics

- `int_transactions_classified` applies Plaid flow categories and ordered
  merchant overrides from `seeds/reference/category_rules.csv`.
- Category rules use lowercase regular expressions. Lower priority numbers win
  when multiple enabled rules match.
- `int_transfer_matches` pairs equal-and-opposite transactions across different
  accounts using mutual-best matching within three calendar days. Checking
  outflows paired with credit inflows are treated as card payments.
- `fct_transactions` exposes `income_amount`, `spending_amount`,
  `unmatched_refund_amount`, `reporting_date`, and `reporting_category` so every
  downstream total can be traced to its contributing transaction rows.
- `fct_monthly_cashflow` excludes transfers and card payments, nets only matched
  refunds against spending, and calculates savings rate only when income is nonzero.
- `fct_monthly_spending_by_category` uses the same canonical transaction model,
  so dashboard totals and category drill-downs reconcile.

## Comparable periods

- `fct_cashflow_periods` uses the shared `fct_data_status` cutoff. All expected
  accounts must have a fresh sync with `HISTORICAL_UPDATE_COMPLETE` and pass
  source-to-canonical reconciliation before comparable periods are emitted.
- Current MTD, prior-month, and prior-year periods use the same number of
  calendar days, capped at each comparison month's last day.
- `fct_mtd_comparison` exposes absolute and percentage changes. Percentage
  changes are null when the comparison baseline is zero.

## Recurring purchases and outliers

- Recurring candidates require at least three expenses at the same normalized
  merchant and category.
- Supported cadences are weekly, monthly, quarterly, and annual.
- At least 75% of amounts must be within 20% of the median amount, and at least
  75% of intervals must fall within the cadence tolerance.
- Outliers use category median and median absolute deviation when at least five
  comparable expenses exist.
- Mature cohorts require an absolute amount of at least $250, at least three
  times the category median, and a modified z-score of at least 5.
- Categories with fewer than five expenses use a $1,000 absolute threshold;
  a single large purchase can be flagged without an established baseline.
- Every recurring and outlier row includes its baseline and a readable
  detection reason.

Amount tolerance and minimum consistency can be configured with
`recurring_amount_tolerance` (default 0.20) and `recurring_min_consistency`
(default 0.75). Recurring results are candidates, not confirmed subscriptions.

## Refund treatment

`int_refund_matches` automatically matches only a unique full refund to a unique
purchase on the same account, with the same merchant (ignoring case and outer
whitespace), the same absolute amount, and a purchase date within the preceding
180 days. Configure the window with `refund_match_days`.

A matched refund reduces spending in the original purchase's category and
period. Posted date, raw amount, original category, and both transaction IDs
remain available for drill-down. This restates the original period; it is an
analytical allocation, not a bank balance movement in that period. Fully refunded
purchases do not contribute to recurring or outlier detection.

Partial, ambiguous, older, and cross-account refunds remain separate as
`unmatched_refunds`; they do not reduce spending or increase income. Matching is
a conservative heuristic, not a bank-provided purchase/refund link.

## Account freshness and reconciliation

- `fct_account_status` distinguishes the latest posted transaction from the
  latest completed sync, including syncs with no transaction changes.
- Coverage is conservatively estimated through the **previous calendar day in
  America/New_York** at the time of each completed sync. Plaid does not provide a
  bank-certified fully posted-through date in these batches; late postings can
  still restate results. The dashboard must display this limitation.
- `expected_accounts.csv` requires one WF checking, one WF credit, and one Amex
  credit account. Missing, extra, incomplete, stale, or future-dated account
  coverage prevents reporting. Fresh means synced on the reporting date in
  New York. Production uses the build's date; fixture builds use July 4, 2026.
- `fct_account_reconciliation` compares posted source counts and signed totals
  with the canonical facts, after latest-version deduplication and pending
  exclusion. It also reports uncategorized transactions, unmatched transfers,
  unmatched refunds, pending records, and duplicate records. Production event
  replay already collapses duplicate versions before these counts are measured.
- `fct_data_status` supplies the shared cutoff (the earliest account coverage),
  newest/oldest account sync times, quality warning counts, currency, and timezone.
  dbt fails the reporting readiness test on incomplete coverage or reconciliation
  failure; the curated exporter independently rejects a non-ready status.
- **Statement/balance reconciliation remains `not_available`.** This validates
  the pipeline against its imported source, not against bank statements. No
  opening/closing balances or statement totals are currently supplied.

Canonical transactions and the three quality models have enforced dbt column
contracts in `models/schema.yml`.

## Validation

From the repository root, using Git Bash:

```bash
uv run python -m unittest discover -s transform/test_python -v
uv run python -m unittest discover -s tools/curated-publish/test -p 'test_*.py' -v
npm --prefix tools/plaid-sync test
npm --prefix tools/curated-publish test
cd transform
uv run dbt --no-partial-parse build --profiles-dir . --target dev
```

The Python analytics suite executes the actual SQL in an in-memory DuckDB with
synthetic input. It covers refund ambiguity, partial refunds, cross-period
allocation, missing/stale/quiet accounts, DST boundaries, short months, leap
years, zero baselines, lost/changed records, latest pending versions, production
event replay, recurring cadence/variance, and outlier edge cases.

See [the manually checked fixture period](validation.md). CSV fallback ingestion,
bank-statement comparison, Evidence pages, and daily reporting/automation remain
separate project milestones.

For reviewing actual data and business-rule assumptions, use the
[manual review guide](manual-review.md) and its local HTML report command.
Card-payment classification explicitly recognizes
`LOAN_PAYMENTS_CREDIT_CARD_PAYMENT` on both sides of a payment, in addition to
the transfer-style payment labels. A dedicated regression test checks that none
of these entries contribute to income, spending, or unmatched refunds.
