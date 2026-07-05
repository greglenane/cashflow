# Cashflow transformations

This dbt project currently runs only against synthetic Plaid-shaped seeds.
Nothing in this project reads AWS credentials, Secrets Manager, or the private
S3 bucket.

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
- `fct_monthly_cashflow` excludes transfers and card payments, nets refunds
  against spending, and calculates savings rate only when income is nonzero.
- `fct_monthly_spending_by_category` uses the same canonical transaction model,
  so dashboard totals and category drill-downs reconcile.

## Comparable periods

- `fct_cashflow_periods` derives the cutoff from the latest imported
  transaction date.
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
- Categories with fewer than five expenses use a conservative $1,000 and
  three-times-median fallback.
- Every recurring and outlier row includes its baseline and a readable
  detection reason.

The classification rules are intentionally minimal. Transfer pairing,
user-overridable categorization, and production S3 ingestion belong in later
models with dedicated tests.
