# Cashflow Dashboard

Private cashflow analytics built with Evidence, dbt, DuckDB, S3, and Plaid.

Development is guided by [AGENTS.md](./AGENTS.md). The one-time local account
linking utility is documented in
[tools/plaid-linker/README.md](./tools/plaid-linker/README.md).
Incremental transaction ingestion is documented in
[tools/plaid-sync/README.md](./tools/plaid-sync/README.md).

## Local transformation

The dbt/DuckDB project lives in [`transform`](./transform). It defaults to
synthetic fixture data and does not read S3 or require AWS credentials.

From Git Bash:

```bash
uv sync
cd transform
uv run dbt build --profiles-dir .
```

The local DuckDB database is written beneath `.local/` and is ignored by Git.

AWS role setup for the transformation layer is documented in
[`infra/iam/README.md`](./infra/iam/README.md).
Curated Parquet export and encrypted S3 publication are documented in
[`tools/curated-publish/README.md`](./tools/curated-publish/README.md).

The analytics foundation includes conservative refund allocation, account-level
sync coverage, pipeline reconciliation, and a fail-closed reporting status.
See [`transform/README.md`](./transform/README.md) for definitions and tests and
[`transform/validation.md`](./transform/validation.md) for manually checked
synthetic totals. The next milestone is the local Evidence dashboard; no Evidence
site or daily report workflow has been scaffolded yet.

For checking the rules against your intentions and privately comparing actual
transactions with your banks, follow [`transform/manual-review.md`](./transform/manual-review.md).
It includes the command for generating a local HTML review from the shared models.
