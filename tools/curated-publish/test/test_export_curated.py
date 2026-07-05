import sys
import unittest
from datetime import date, datetime, timezone
from pathlib import Path

import duckdb

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from export_curated import export_curated


class ExportCuratedTest(unittest.TestCase):
    def test_exports_deterministic_year_partitions_and_manifest(self):
        root = (
            Path(__file__).resolve().parents[3]
            / ".local"
            / "export-test"
        )
        root.mkdir(parents=True, exist_ok=True)
        database = root / "fixture.duckdb"
        if database.exists():
            database.unlink()
        output = root / ".local" / "curated" / "current"
        connection = duckdb.connect(str(database))
        connection.execute("create schema analytics")
        connection.execute(
            """
            create table analytics.fct_transactions (
                transaction_id varchar,
                account_id varchar,
                account_name varchar,
                account_type varchar,
                transaction_date date,
                description_raw varchar,
                merchant_normalized varchar,
                amount decimal(18, 2),
                flow_type varchar,
                category varchar,
                source varchar,
                source_file varchar,
                imported_at timestamptz
            )
            """
        )
        connection.executemany(
            """
            insert into analytics.fct_transactions
            values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (
                    "txn-2025",
                    "acct",
                    "Synthetic",
                    "checking",
                    date(2025, 12, 31),
                    "Synthetic",
                    "Synthetic",
                    -10,
                    "expense",
                    "test",
                    "plaid",
                    "fixture",
                    datetime(2026, 1, 1, tzinfo=timezone.utc),
                ),
                (
                    "txn-2026",
                    "acct",
                    "Synthetic",
                    "checking",
                    date(2026, 1, 1),
                    "Synthetic",
                    "Synthetic",
                    100,
                    "income",
                    "income",
                    "plaid",
                    "fixture",
                    datetime(2026, 1, 2, tzinfo=timezone.utc),
                ),
            ],
        )
        connection.execute(
            """
            create table analytics.stg_plaid_accounts as
            select
                'acct'::varchar as account_id,
                'Synthetic'::varchar as account_name,
                'checking'::varchar as account_type,
                'synthetic'::varchar as institution
            """
        )
        connection.close()

        first = export_curated(database, output)
        second = export_curated(database, output)

        self.assertEqual(first["run_id"], second["run_id"])
        self.assertEqual(first["total_transactions"], 2)
        self.assertEqual(len(first["files"]), 3)
        self.assertTrue(
            (
                output
                / "transactions/year=2025/transactions.parquet"
            ).is_file()
        )
        self.assertTrue(
            (
                output
                / "transactions/year=2026/transactions.parquet"
            ).is_file()
        )
        self.assertTrue((output / "accounts/accounts.parquet").is_file())


if __name__ == "__main__":
    unittest.main()
