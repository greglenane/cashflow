# Curated Parquet publisher

This tool exports tested dbt models from the ignored local production DuckDB
database, then uploads them to the private `cashflow-dashboard` bucket.

Publication order:

1. One Zstandard-compressed transaction file per calendar year
2. One masked account metadata file
3. Shared monthly and matched-period cashflow metric files
4. Explainable recurring-purchase and outlier files
5. Account freshness, pipeline reconciliation, and shared data-status files
6. An immutable run manifest
7. `curated/manifests/latest.json`

All uploads request SSE-S3 (`AES256`). Object keys and the run ID are
deterministic, so rerunning unchanged data overwrites the same versioned keys.
The publisher has no delete permission.

The export requires `fct_data_status.ready_for_reporting` and a non-null shared
cutoff. It takes cutoff/refresh metadata from that model, including zero-change
syncs, rather than inferring freshness from transaction dates. Transaction files
include refund links and the canonical reporting date/category and metric
contributions. Quality files are private just like the transaction files.

Run the complete dbt build first. From the repository root:

```bash
uv run python tools/curated-publish/export_curated.py
```

Then export temporary transform-role credentials and publish:

```bash
eval "$(
  aws configure export-credentials \
    --profile cashflow-transform \
    --format env
)"
export AWS_REGION=us-east-1

npm --prefix tools/curated-publish start

unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_CREDENTIAL_EXPIRATION
```

Generated Parquet and manifest files remain under `.local/curated/current/` and
must never be committed or shared.
