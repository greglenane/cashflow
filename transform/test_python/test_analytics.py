"""Execute the actual dbt SQL in memory with synthetic inputs and fixed dates.

No AWS, Plaid, production database, or generated dbt artifacts are read.
"""
import json
import unittest
from datetime import date, datetime, timezone
from pathlib import Path
from types import SimpleNamespace

import duckdb
from jinja2 import Environment, StrictUndefined


PROJECT = Path(__file__).resolve().parents[1]
MODELS = {path.stem: path for path in (PROJECT / "models").rglob("*.sql")}
ORDER = [
    "stg_plaid_accounts", "stg_plaid_transactions", "stg_plaid_sync_status",
    "int_transactions_classified", "int_transfer_matches", "int_refund_matches",
    "fct_transactions", "fct_account_status", "fct_account_reconciliation",
    "fct_data_status", "fct_monthly_cashflow", "fct_monthly_spending_by_category",
    "fct_cashflow_periods", "fct_mtd_comparison", "fct_recurring_purchases",
    "fct_outlier_purchases",
]


class AnalyticsTest(unittest.TestCase):
    def setUp(self):
        self.db = duckdb.connect(":memory:")
        self.addCleanup(self.db.close)
        for path in (PROJECT / "seeds").rglob("*.csv"):
            self.db.execute(
                f'create table "{path.stem}" as select * from read_csv_auto(?)',
                [str(path)],
            )
        self.build()

    def model(self, name, target="dev", variables=None):
        variables = variables or {}
        sql = Environment(undefined=StrictUndefined).from_string(
            MODELS[name].read_text(encoding="utf-8")
        ).render(
            ref=lambda name: f'"{name}"', config=lambda **kwargs: "",
            var=lambda name, default=None: variables.get(name, default),
            target=SimpleNamespace(name=target),
            run_started_at=datetime(2026, 7, 4, 12, tzinfo=timezone.utc),
        )
        self.db.execute(f'create or replace table "{name}" as {sql}')

    def build(self):
        for name in ORDER:
            self.model(name)

    def rows(self, sql):
        return self.db.execute(sql).fetchall()

    def transaction(self, identifier, amount, day="2026-07-02", merchant="Test Store",
                    account="acct_amex_credit", category="GENERAL_MERCHANDISE",
                    pending=False, imported="2026-07-04T08:00:00Z"):
        self.db.execute(
            "insert into plaid_transactions values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [identifier, account, day, merchant, merchant, amount, category,
             category + "_OTHER", pending, "synthetic_test", imported],
        )

    def test_manually_reconciled_fixture(self):
        # July purchases: 125.50 + 80 + 65 + 20 = 290.50. The partial
        # cafe refund (20) is separate; the 500 payment on each side is excluded.
        self.assertEqual(self.rows("""
            select income, spending, unmatched_refunds, net_cashflow, savings_rate
            from fct_monthly_cashflow where month_start = date '2026-07-01'
        """), [(0, 290.5, 20, -290.5, None)])
        self.assertEqual(self.rows("""
            select income, spending, net_cashflow, savings_rate
            from fct_monthly_cashflow where month_start = date '2026-06-01'
        """), [(2500, 120, 2380, 0.952)])
        self.assertEqual(self.rows("select count(*) from fct_transactions"), [(17,)])
        self.assertEqual(self.rows("""
            select sum(count_difference), sum(amount_difference),
                sum(duplicate_record_count), sum(pending_count)
            from fct_account_reconciliation
        """), [(0, 0, 1, 1)])

    def test_deli_override_wins_over_plaid_category_without_matching_other_names(self):
        # User-specified merchant name, with invented records and amounts only.
        self.db.execute("delete from plaid_transactions")
        self.transaction("synthetic_deli_purchase", 12, merchant="SYNTHETIC QUINCY MARKET FIXTURE")
        self.transaction("synthetic_deli_refund", -3, merchant="synthetic quincy market fixture")
        self.transaction("synthetic_deli_spacing", 8, merchant="QUINCY  MARKET SYNTHETIC")
        self.transaction("synthetic_other_merchant", 9, merchant="SYNTHETIC QUINCY MARKETPLACE")
        self.build()
        self.assertEqual(self.rows("""
            select transaction_id, category, category_rule_id
            from fct_transactions order by transaction_id
        """), [
            ("synthetic_deli_purchase", "Food & Drink", "quincy_market_food_drink"),
            ("synthetic_deli_refund", "Food & Drink", "quincy_market_food_drink"),
            ("synthetic_deli_spacing", "Food & Drink", "quincy_market_food_drink"),
            ("synthetic_other_merchant", "Shopping", None),
        ])

    def test_refunds_match_only_unique_full_purchase_and_restate_its_period(self):
        self.db.execute("delete from plaid_transactions")
        self.transaction("purchase", 80, "2026-06-28", category="HOME_IMPROVEMENT")
        self.transaction("refund", -80, "2026-07-03", merchant=" test store ")
        self.transaction("partial_purchase", 65, merchant="Cafe")
        self.transaction("partial_refund", -20, merchant="Cafe")
        self.transaction("ambiguous_a", 30, merchant="Repeated")
        self.transaction("ambiguous_b", 30, merchant="Repeated")
        self.transaction("ambiguous_refund", -30, merchant="Repeated")
        self.transaction("double_purchase", 40, merchant="Double")
        self.transaction("double_refund_a", -40, merchant="Double")
        self.transaction("double_refund_b", -40, merchant="Double")
        self.transaction("old_purchase", 25, "2025-01-01", merchant="Old")
        self.transaction("old_refund", -25, merchant="Old")
        self.transaction("other_account_purchase", 100, account="acct_wf_credit")
        self.transaction("other_account_refund", -100)
        self.build()
        self.assertEqual(self.rows("""
            select refund_transaction_id, purchase_transaction_id from int_refund_matches
        """), [("refund", "purchase")])
        self.assertEqual(self.rows("""
            select transaction_date, reporting_date, reporting_category, spending_amount
            from fct_transactions where transaction_id = 'refund'
        """), [(date(2026, 7, 3), date(2026, 6, 28), "Home Improvement", -80)])
        self.assertEqual(self.rows("""
            select spending from fct_monthly_cashflow where month_start = date '2026-06-01'
        """), [(0,)])
        self.assertEqual(self.rows("select sum(unmatched_refund_amount) from fct_transactions"), [(255,)])

    def test_short_months_leap_year_and_zero_baseline(self):
        for cutoff, prior_end, year_end in [
            ("2026-03-31", date(2026, 2, 28), date(2025, 3, 31)),
            ("2024-03-31", date(2024, 2, 29), date(2023, 3, 31)),
            ("2024-02-29", date(2024, 1, 29), date(2023, 2, 28)),
            ("2026-01-31", date(2025, 12, 31), date(2025, 1, 31)),
        ]:
            with self.subTest(cutoff=cutoff):
                self.db.execute("update fct_data_status set data_cutoff_date = ?", [cutoff])
                self.model("fct_cashflow_periods")
                periods = dict(self.rows("select period_name, period_end from fct_cashflow_periods"))
                self.assertEqual(periods["prior_month_comparable"], prior_end)
                self.assertEqual(periods["prior_year_comparable"], year_end)
                self.model("fct_mtd_comparison")
                self.assertEqual(self.rows("select spending_pct_change_vs_prior_month from fct_mtd_comparison"), [(None,)])

    def test_missing_stale_incomplete_or_future_account_blocks_reporting(self):
        for change, status in [
            ("delete from plaid_sync_status where institution = 'amex'", "missing_sync"),
            ("update plaid_sync_status set last_synced_at = '2026-07-03T09:00:00Z' where institution = 'amex'", "stale"),
            ("update plaid_sync_status set update_status = 'NOT_READY' where institution = 'amex'", "incomplete_history"),
            ("update plaid_sync_status set last_synced_at = '2026-07-05T09:00:00Z' where institution = 'amex'", "future_sync"),
        ]:
            with self.subTest(status=status):
                self.db.execute("create or replace table saved_status as select * from plaid_sync_status")
                self.db.execute(change)
                self.build()
                self.assertEqual(self.rows("select freshness_status from fct_account_status where institution = 'amex'"), [(status,)])
                self.assertEqual(self.rows("select ready_for_reporting, data_cutoff_date from fct_data_status"), [(False, None)])
                self.assertEqual(self.rows("select count(*) from fct_cashflow_periods"), [(0,)])
                self.db.execute("create or replace table plaid_sync_status as select * from saved_status")

    def test_absent_expected_account_and_extra_account_block_coverage(self):
        self.db.execute("delete from plaid_accounts where institution = 'amex'")
        self.build()
        self.assertEqual(self.rows("select account_coverage_complete from fct_data_status"), [(False,)])
        self.db.execute("insert into plaid_accounts values ('extra', 'Synthetic', 'checking', 'other')")
        self.build()
        self.assertEqual(self.rows("select ready_for_reporting from fct_data_status"), [(False,)])

    def test_quiet_account_is_current_when_zero_change_sync_completed(self):
        self.db.execute("delete from plaid_transactions where account_id = 'acct_amex_credit'")
        self.build()
        self.assertEqual(self.rows("""
            select latest_transaction_date, imported_through_date, freshness_status
            from fct_account_status where institution = 'amex'
        """), [(None, date(2026, 7, 3), "ready")])
        self.assertEqual(self.rows("select ready_for_reporting from fct_data_status"), [(True,)])

    def test_new_york_date_boundary_and_dst(self):
        for timestamp, as_of, cutoff in [
            ("2026-07-04T03:59:00Z", "2026-07-03", date(2026, 7, 2)),
            ("2026-07-04T04:01:00Z", "2026-07-04", date(2026, 7, 3)),
            ("2026-01-04T04:59:00Z", "2026-01-03", date(2026, 1, 2)),
            ("2026-01-04T05:01:00Z", "2026-01-04", date(2026, 1, 3)),
        ]:
            self.db.execute("update plaid_sync_status set last_synced_at = ?", [timestamp])
            self.model("stg_plaid_sync_status")
            self.model("fct_account_status", variables={"reporting_as_of_date": as_of})
            self.assertEqual(self.rows("select distinct imported_through_date, freshness_status from fct_account_status"), [(cutoff, "ready")])

    def test_reconciliation_detects_lost_or_changed_canonical_rows(self):
        for mutation in [
            "update fct_transactions set amount = amount - 1 where transaction_id = 'txn_grocery'",
            "delete from fct_transactions where transaction_id = 'txn_grocery'",
        ]:
            self.build()
            self.db.execute(mutation)
            self.model("fct_account_reconciliation")
            self.model("fct_data_status")
            self.assertEqual(self.rows("select ready_for_reporting from fct_data_status"), [(False,)])

    def test_latest_pending_version_excludes_older_posted_version(self):
        self.transaction("txn_grocery", 130, account="acct_wf_checking", pending=True)
        self.build()
        self.assertEqual(self.rows("select count(*) from fct_transactions where transaction_id = 'txn_grocery'"), [(0,)])
        self.assertEqual(self.rows("select sum(count_difference) from fct_account_reconciliation"), [(0,)])

    def test_reimporting_identical_source_rows_does_not_duplicate_metrics(self):
        before = self.rows("select * from fct_monthly_cashflow order by month_start")
        self.db.execute("insert into plaid_transactions select * from plaid_transactions")
        self.build()
        self.assertEqual(self.rows("select count(*) from fct_transactions"), [(17,)])
        self.assertEqual(self.rows("select * from fct_monthly_cashflow order by month_start"), before)
        self.assertEqual(self.rows("select ready_for_reporting from fct_data_status"), [(True,)])

    def test_plaid_loan_payment_category_excludes_both_card_payment_sides(self):
        self.db.execute("delete from plaid_transactions")
        self.transaction("payment_out", 500, account="acct_wf_checking", category="LOAN_PAYMENTS")
        self.transaction("payment_in", -500, account="acct_wf_credit", category="LOAN_PAYMENTS")
        self.db.execute("""
            update plaid_transactions
            set personal_finance_category_detailed = 'LOAN_PAYMENTS_CREDIT_CARD_PAYMENT'
        """)
        self.build()
        self.assertEqual(self.rows("""
            select flow_type, count(*), sum(income_amount), sum(spending_amount),
                sum(unmatched_refund_amount), count(matched_transaction_id)
            from fct_transactions group by flow_type
        """), [("card_payment", 2, 0, 0, 0, 2)])

    def test_single_large_purchase_and_zero_mad_and_nonexpenses(self):
        self.db.execute("delete from plaid_transactions")
        self.transaction("large", 1500, category="TRAVEL")
        for i in range(4):
            self.transaction(f"ordinary_{i}", 10)
        self.transaction("zero_mad", 300)
        self.transaction("refund", -2000, category="MEDICAL")
        self.transaction("income", -3000, category="INCOME")
        self.transaction("transfer", 4000, category="TRANSFER_OUT")
        self.build()
        self.assertEqual(set(self.rows("select transaction_id, flag_method from fct_outlier_purchases")), {
            ("large", "limited_history_threshold"), ("zero_mad", "zero_mad_fallback"),
        })

    def test_recurring_cadences_and_high_frequency_and_variance(self):
        self.db.execute("delete from plaid_transactions")
        groups = {
            "weekly": ["2026-06-01", "2026-06-08", "2026-06-15"],
            "monthly": ["2026-04-30", "2026-05-31", "2026-06-30"],
            "quarterly": ["2026-01-01", "2026-04-01", "2026-07-01"],
            "annual": ["2024-01-01", "2025-01-01", "2026-01-01"],
            "daily": ["2026-06-01", "2026-06-02", "2026-06-03"],
            "two_only": ["2026-05-01", "2026-06-01"],
            "variable": ["2026-04-01", "2026-05-01", "2026-06-01"],
        }
        for merchant, days in groups.items():
            for i, day in enumerate(days):
                amount = (10, 100, 1000)[i] if merchant == "variable" else 20
                self.transaction(f"{merchant}_{i}", amount, day, merchant)
        self.build()
        self.assertEqual(set(self.rows("select merchant_normalized, cadence from fct_recurring_purchases")), {
            (cadence, cadence) for cadence in ["weekly", "monthly", "quarterly", "annual"]
        })

    def test_production_replay_removal_modification_and_zero_change_batch(self):
        transaction = dict(transaction_id="synthetic", account_id="acct_amex_credit",
                           date="2026-07-01", name="Synthetic", merchant_name="Synthetic",
                           amount=10, pending=False)
        account = dict(account_id="acct_amex_credit", type="credit", subtype="credit card",
                       mask="3333", name="Synthetic")
        batches = [
            dict(added=[transaction], modified=[], removed=[]),
            dict(added=[], modified=[{**transaction, "amount": 20}], removed=[]),
            dict(added=[], modified=[], removed=[{"transaction_id": "synthetic"}]),
            dict(added=[], modified=[], removed=[]),
        ]
        self.db.execute("create table int_plaid_raw_batches (source_file varchar, batch json)")
        for index, events in enumerate(batches):
            batch = dict(**events, institution="amex", batch_id=str(index),
                         fetched_at=f"2026-07-0{index + 1}T09:00:00Z", accounts=[account],
                         transactions_update_status="HISTORICAL_UPDATE_COMPLETE")
            self.db.execute("insert into int_plaid_raw_batches values (?, ?)", [f"fixture_{index}", json.dumps(batch)])
            self.model("int_plaid_transaction_events", target="prod")
            self.model("int_plaid_current_transactions", target="prod")
            expected = [(10,)] if index == 0 else [(20,)] if index == 1 else []
            self.assertEqual(self.rows("select plaid_amount from int_plaid_current_transactions"), expected)
        self.model("int_plaid_current_accounts", target="prod")
        self.model("stg_plaid_sync_status", target="prod")
        self.assertEqual(self.rows("select cast(last_synced_at as date) from stg_plaid_sync_status"), [(date(2026, 7, 4),)])
        # A newer incomplete sync must not fall back to the older complete one.
        batch["fetched_at"] = "2026-07-05T09:00:00Z"
        batch["transactions_update_status"] = "NOT_READY"
        self.db.execute("insert into int_plaid_raw_batches values ('incomplete', ?)", [json.dumps(batch)])
        self.model("stg_plaid_sync_status", target="prod")
        self.assertEqual(self.rows("select update_status from stg_plaid_sync_status"), [("NOT_READY",)])


if __name__ == "__main__":
    unittest.main()
