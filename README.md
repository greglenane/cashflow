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
