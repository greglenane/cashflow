# Plaid Transaction Sync

This command performs an incremental Plaid `/transactions/sync` for Wells Fargo
and American Express.

It reads:

- `cashflow/plaid/production`
- `cashflow/plaid/items/wells-fargo`
- `cashflow/plaid/items/amex`
- `s3://cashflow-dashboard/state/plaid/*.json`

It writes:

- Immutable raw batches under `s3://cashflow-dashboard/raw/plaid/`
- One cursor state object per institution under
  `s3://cashflow-dashboard/state/plaid/`

The raw batch is written before cursor state advances. S3 conditional writes
protect the cursor from overlapping runs.

Schema version 2 raw batches also contain sanitized account metadata:
`account_id`, type, subtype, mask, and name. Access tokens, item IDs, and Plaid
API credentials are never written to raw batches or logs.

## Install

From the repository root in Git Bash:

```bash
cd tools/plaid-sync
npm install
```

## Run locally

Refresh the base login if necessary:

```bash
aws login --profile cashflow-mcp
```

Export temporary sync-role credentials into this terminal:

```bash
eval "$(
  aws configure export-credentials \
    --profile cashflow-sync \
    --format env
)"
export AWS_REGION=us-east-1
```

Run:

```bash
npm start
```

The command logs only institution names and change counts. It does not log
transactions, Plaid credentials, access tokens, cursors, or S3 object contents.

Close the terminal after the run to discard temporary credentials.

## Test

Tests are synthetic and make no Plaid or AWS calls:

```bash
npm test
```
