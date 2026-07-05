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

The classification rules are intentionally minimal. Transfer pairing,
user-overridable categorization, and production S3 ingestion belong in later
models with dedicated tests.
