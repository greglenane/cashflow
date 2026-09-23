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
                category_rule_id varchar,
                transfer_match_id varchar,
                matched_transaction_id varchar,
                match_date_distance_days bigint,
                source varchar,
                source_file varchar,
                imported_at timestamptz
            )
            """
        )
        connection.executemany(
            """
            insert into analytics.fct_transactions
            values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                    None,
                    None,
                    None,
                    None,
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
                    None,
                    None,
                    None,
                    None,
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
        connection.execute(
            """
            create table analytics.fct_monthly_cashflow as
            select
                date '2026-01-01' as month_start,
                100::decimal(18, 2) as income,
                0::decimal(18, 2) as gross_spending,
                0::decimal(18, 2) as refunds,
                0::decimal(18, 2) as spending,
                100::decimal(18, 2) as net_cashflow,
                1::bigint as included_transaction_count,
                1::decimal(18, 4) as savings_rate
            """
        )
        connection.execute(
            """
            create table analytics.fct_monthly_spending_by_category as
            select
                date '2025-12-01' as month_start,
                'test'::varchar as category,
                10::decimal(18, 2) as spending,
                1::bigint as purchase_count,
                0::bigint as refund_count
            """
        )
        connection.execute(
            """
            create table analytics.fct_cashflow_periods as
            select
                'current_mtd'::varchar as period_name,
                date '2026-01-02' as data_cutoff_date,
                date '2026-01-01' as period_start,
                date '2026-01-02' as period_end,
                2::bigint as comparable_day_count,
                100::decimal(18, 2) as income,
                0::decimal(18, 2) as spending,
                100::decimal(18, 2) as net_cashflow,
                1::decimal(18, 4) as savings_rate
            """
        )
        connection.execute(
            """
            create table analytics.fct_mtd_comparison as
            select
                date '2026-01-02' as data_cutoff_date,
                2::bigint as comparable_day_count,
                0::decimal(18, 2) as current_spending
            """
        )
        connection.execute(
            """
            create table analytics.fct_recurring_purchases as
            select
                'recurring'::varchar as recurring_id,
                'Synthetic'::varchar as merchant_normalized,
                'Test'::varchar as category
            """
        )
        connection.execute(
            """
            create table analytics.fct_outlier_purchases as
            select
                'outlier'::varchar as transaction_id,
                date '2026-01-01' as transaction_date
            """
        )
        for column, data_type in [
            ("matched_purchase_id", "varchar"),
            ("matched_refund_id", "varchar"),
            ("refund_status", "varchar"),
            ("reporting_date", "date"),
            ("reporting_category", "varchar"),
            ("income_amount", "decimal(18, 2)"),
            ("spending_amount", "decimal(18, 2)"),
            ("unmatched_refund_amount", "decimal(18, 2)"),
        ]:
            connection.execute(
                f"alter table analytics.fct_transactions add column {column} {data_type}"
            )
        connection.execute("""
            create table analytics.fct_data_status as
            select true as ready_for_reporting,
                date '2026-01-02' as data_cutoff_date,
                timestamptz '2026-01-03 09:00:00+00' as source_refresh_time
        """)
        for table in ("fct_account_status", "fct_account_reconciliation"):
            connection.execute(
                f"create table analytics.{table} as select 'acct' as account_id"
            )
        connection.close()

        first = export_curated(database, output)
        second = export_curated(database, output)

        self.assertEqual(first["run_id"], second["run_id"])
        self.assertEqual(first["total_transactions"], 2)
        self.assertEqual(len(first["files"]), 12)
        self.assertEqual(first["source_data_cutoff"], "2026-01-02")
        self.assertTrue(first["source_refresh_time"].startswith("2026-01-03"))
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
        self.assertTrue(
            (output / "metrics/monthly_cashflow.parquet").is_file()
        )
        self.assertTrue(
            (
                output
                / "metrics/monthly_spending_by_category.parquet"
            ).is_file()
        )
        self.assertTrue(
            (output / "metrics/cashflow_periods.parquet").is_file()
        )
        self.assertTrue(
            (output / "metrics/mtd_comparison.parquet").is_file()
        )
        self.assertTrue(
            (output / "analytics/recurring_purchases.parquet").is_file()
        )
        self.assertTrue(
            (output / "analytics/outlier_purchases.parquet").is_file()
        )
        self.assertTrue((output / "quality/account_status.parquet").is_file())
        self.assertTrue((output / "quality/account_reconciliation.parquet").is_file())
        self.assertTrue((output / "quality/data_status.parquet").is_file())

        # A failed coverage check must preserve the last good local export.
        manifest_before = (output / "manifest.json").read_bytes()
        connection = duckdb.connect(str(database))
        connection.execute("update analytics.fct_data_status set ready_for_reporting = false")
        connection.close()
        with self.assertRaisesRegex(ValueError, "complete, reconciled"):
            export_curated(database, output)
        self.assertEqual((output / "manifest.json").read_bytes(), manifest_before)


if __name__ == "__main__":
    unittest.main()
