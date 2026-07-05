from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

import duckdb


TRANSACTION_COLUMNS = """
    transaction_id,
    account_id,
    account_name,
    account_type,
    transaction_date,
    description_raw,
    merchant_normalized,
    amount,
    flow_type,
    category,
    source,
    source_file,
    imported_at
"""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sql_string(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def reset_output_directory(output_directory: Path) -> None:
    resolved = output_directory.resolve()
    if (
        resolved.name != "current"
        or resolved.parent.name != "curated"
        or resolved.parent.parent.name != ".local"
    ):
        raise ValueError(
            "Output directory must end with .local/curated/current"
        )

    if resolved.exists():
        shutil.rmtree(resolved)
    resolved.mkdir(parents=True)


def file_entry(
    output_directory: Path,
    relative_key: str,
    row_count: int,
) -> dict[str, object]:
    path = output_directory / Path(relative_key)
    return {
        "key": relative_key,
        "content_type": "application/vnd.apache.parquet",
        "row_count": row_count,
        "size_bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def export_curated(
    database_path: Path,
    output_directory: Path,
) -> dict[str, object]:
    database_path = database_path.resolve()
    output_directory = output_directory.resolve()
    reset_output_directory(output_directory)

    connection = duckdb.connect(str(database_path), read_only=True)
    try:
        years = [
            row[0]
            for row in connection.execute(
                """
                select distinct year(transaction_date) as transaction_year
                from analytics.fct_transactions
                where transaction_date is not null
                order by transaction_year
                """
            ).fetchall()
        ]

        files: list[dict[str, object]] = []
        total_transactions = 0
        for year in years:
            relative_key = (
                f"transactions/year={year}/transactions.parquet"
            )
            destination = output_directory / Path(relative_key)
            destination.parent.mkdir(parents=True, exist_ok=True)
            row_count = connection.execute(
                """
                select count(*)
                from analytics.fct_transactions
                where year(transaction_date) = ?
                """,
                [year],
            ).fetchone()[0]
            connection.execute(
                f"""
                copy (
                    select {TRANSACTION_COLUMNS}
                    from analytics.fct_transactions
                    where year(transaction_date) = ?
                    order by transaction_date, transaction_id
                ) to {sql_string(str(destination))} (
                    format parquet,
                    compression zstd,
                    compression_level 3
                )
                """,
                [year],
            )
            files.append(
                file_entry(output_directory, relative_key, row_count)
            )
            total_transactions += row_count

        accounts_key = "accounts/accounts.parquet"
        accounts_path = output_directory / Path(accounts_key)
        accounts_path.parent.mkdir(parents=True, exist_ok=True)
        account_count = connection.execute(
            "select count(*) from analytics.stg_plaid_accounts"
        ).fetchone()[0]
        connection.execute(
            f"""
            copy (
                select
                    account_id,
                    account_name,
                    account_type,
                    institution
                from analytics.stg_plaid_accounts
                order by account_id
            ) to {sql_string(str(accounts_path))} (
                format parquet,
                compression zstd,
                compression_level 3
            )
            """
        )
        files.append(
            file_entry(output_directory, accounts_key, account_count)
        )

        source_data_cutoff, source_refresh_time = connection.execute(
            """
            select
                max(transaction_date),
                max(imported_at)
            from analytics.fct_transactions
            """
        ).fetchone()
    finally:
        connection.close()

    fingerprint_input = json.dumps(
        {
            "schema_version": 1,
            "files": [
                {
                    "key": file["key"],
                    "row_count": file["row_count"],
                    "sha256": file["sha256"],
                }
                for file in files
            ],
        },
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    run_id = hashlib.sha256(fingerprint_input).hexdigest()[:24]
    manifest = {
        "schema_version": 1,
        "run_id": run_id,
        "source_data_cutoff": (
            source_data_cutoff.isoformat()
            if source_data_cutoff is not None
            else None
        ),
        "source_refresh_time": (
            source_refresh_time.isoformat()
            if source_refresh_time is not None
            else None
        ),
        "total_transactions": total_transactions,
        "account_count": account_count,
        "files": files,
    }
    manifest_path = output_directory / "manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--database",
        type=Path,
        default=Path(".local/cashflow-prod.duckdb"),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(".local/curated/current"),
    )
    args = parser.parse_args()

    manifest = export_curated(args.database, args.output)
    print(
        "[curated-export]"
        f" run_id={manifest['run_id']}"
        f" files={len(manifest['files'])}"
        f" transactions={manifest['total_transactions']}"
        f" cutoff={manifest['source_data_cutoff']}"
    )


if __name__ == "__main__":
    main()
