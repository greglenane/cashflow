"""Create a private local HTML audit report from shared analytics models."""
from __future__ import annotations

import argparse
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from html import escape
from pathlib import Path

import duckdb


ROOT = Path(__file__).resolve().parents[2]


def display(value):
    if value is None:
        return "—"
    if isinstance(value, Decimal):
        return f"{value:,.2f}"
    if isinstance(value, float):
        return f"{value:,.4f}"
    return str(value)


def render_table(connection, title, note, sql, params=None, section_id=None):
    cursor = connection.execute(sql, params or [])
    headings = [column[0] for column in cursor.description]
    rows = cursor.fetchall()
    head = "".join(f"<th>{escape(column.replace('_', ' '))}</th>" for column in headings)
    body = "".join("<tr>" + "".join(f"<td>{escape(display(value))}</td>" for value in row) + "</tr>" for row in rows)
    anchor = f' id="{escape(section_id, quote=True)}"' if section_id else ""
    return (
        f"<section{anchor}><h2>{escape(title)}</h2><p>{escape(note)}</p>"
        f"<p>{len(rows)} rows</p><div class='scroll'><table><thead><tr>{head}</tr></thead>"
        f"<tbody>{body}</tbody></table></div></section>"
    )


def generate(database, month=None):
    connection = duckdb.connect(str(database.resolve()), read_only=True)
    try:
        status = connection.execute("""
            select ready_for_reporting, data_cutoff_date, latest_transaction_date
            from analytics.fct_data_status
        """).fetchone()
        if status is None:
            raise ValueError("Missing data status")
        cutoff = status[1] or status[2]
        if cutoff is None and month is None:
            raise ValueError("No dates available; supply --month explicitly")
        start = date.fromisoformat(month + "-01") if month else (cutoff.replace(day=1) - timedelta(days=1)).replace(day=1)
        end = (start.replace(day=28) + timedelta(days=4)).replace(day=1)
        sections = []

        def table(title, note, sql, params=None, section_id=None):
            sections.append(render_table(connection, title, note, sql, params, section_id))

        review_columns = """transaction_date, account_name, merchant_normalized,
            description_raw, amount, flow_type, category, refund_status,
            income_amount, spending_amount, unmatched_refund_amount, transaction_id"""
        table("Uncategorized transactions — all history",
              "These have no mapped spending category. Review the merchant and description to decide the appropriate category. This list is not restricted to the report month.",
              f"select {review_columns} from analytics.fct_transactions where category = 'Uncategorized' order by transaction_date desc, transaction_id",
              section_id="uncategorized")
        table("Unpaired transfers and card payments — all history",
              "No matching opposite-side entry was found. These are still excluded from income and spending. Check that each is truly a transfer or card payment; the other account may be outside this project. Rows are entries, not pairs.",
              f"select {review_columns} from analytics.fct_transactions where flow_type in ('transfer', 'card_payment') and transfer_match_id is null order by transaction_date desc, transaction_id",
              section_id="unpaired")
        table("Unmatched refund candidates — all history",
              "These positive receipts were not classified as income or transfers and could not be reliably matched to a full purchase. They currently affect neither income nor spending. Check partial refunds, reimbursements, rewards, and mislabeled income. The review lists can overlap.",
              f"select {review_columns} from analytics.fct_transactions where refund_status = 'unmatched' order by transaction_date desc, transaction_id",
              section_id="unmatched-refunds")

        table("Reporting status", "Amounts are USD; reporting dates use America/New_York. Coverage is estimated, not bank-certified.", "select * from analytics.fct_data_status")
        table("Accounts and history", "Check the three masked accounts and the span of supplied history. No recent purchases can be normal; missing imports are different.", """
            select s.account_name, s.institution, s.account_type,
                h.first_transaction_date, s.latest_transaction_date,
                s.last_synced_at, s.imported_through_date, s.freshness_status
            from analytics.fct_account_status s
            left join (select account_id, min(transaction_date) first_transaction_date
                from analytics.fct_transactions group by account_id) h using (account_id)
            order by institution, account_type
        """)
        table("Pipeline reconciliation", "Compares the imported source with the canonical facts. Statement balances have not been verified.", """
            select s.account_name, r.* exclude(account_id)
            from analytics.fct_account_reconciliation r
            join analytics.fct_account_status s using (account_id)
            order by s.account_name
        """)
        table("Monthly metrics", "All loaded history. Matched full refunds restate their purchase periods; unmatched refunds are separate. Savings rate is a fraction (0.10 = 10%).", "select * from analytics.fct_monthly_cashflow order by month_start desc")
        table("Matched-day comparisons", "No rows means the reporting gate is blocked. Zero historical activity does not prove complete bank history.", "select * from analytics.fct_cashflow_periods order by period_start desc")
        table("Selected month's categories", "These are the shared category totals, using reporting dates.", "select * from analytics.fct_monthly_spending_by_category where month_start = ? order by spending desc", [start])

        columns = """transaction_id, account_name, transaction_date, reporting_date,
            merchant_normalized, description_raw, amount, flow_type, category,
            reporting_category, income_amount, spending_amount, unmatched_refund_amount,
            refund_status, matched_purchase_id, matched_refund_id, matched_transaction_id"""
        table("Posted transactions in the selected month", "Compare these posted dates and amounts with the banks. Positive amounts are receipts; negative amounts are outflows. Pending transactions are excluded.", f"select {columns} from analytics.fct_transactions where transaction_date >= ? and transaction_date < ? order by account_name, transaction_date, transaction_id", [start, end])
        table("Contributors to the selected month's metrics", "Sum income_amount and spending_amount. A refund posted later may appear here because it is allocated to this month's purchase.", f"select {columns} from analytics.fct_transactions where reporting_date >= ? and reporting_date < ? and (income_amount != 0 or spending_amount != 0 or unmatched_refund_amount != 0) order by reporting_date, transaction_id", [start, end])
        table("Refund review — all history", "Every non-income, non-transfer receipt is currently a refund candidate. Check reimbursements, rewards, and mislabeled income especially carefully.", f"select {columns} from analytics.fct_transactions where flow_type = 'refund' order by transaction_date desc, transaction_id")
        table("Transfers and card payments — selected month", "These remain excluded even when no matching entry was found. Confirm that these exclusions are intentional.", f"select {columns} from analytics.fct_transactions where flow_type in ('transfer', 'card_payment') and transaction_date >= ? and transaction_date < ? order by transaction_date, transaction_id", [start, end])
        table("Recurring candidates — all history", "Candidates can include ordinary routine spending or canceled services. Confidence is a heuristic fraction, not a probability. Predictions can be in the past.", "select * exclude(recurring_id) from analytics.fct_recurring_purchases order by monthly_equivalent_cost desc, merchant_normalized")
        table("Outlier flags — all history", "These are statistical flags, not a judgment about the purchase. Compare the baseline and detection reason.", "select * exclude(account_id) from analytics.fct_outlier_purchases order by amount_absolute desc, transaction_id")
        table("Largest expenses — selected month", "Check for important purchases missed by the outlier rule. All posted expenses in the selected month are included, even fully refunded ones.", f"select {columns} from analytics.fct_transactions where flow_type = 'expense' and transaction_date >= ? and transaction_date < ? order by amount, transaction_id", [start, end])

        readiness = "READY FOR REVIEW" if status[0] else "BLOCKED — DIAGNOSTIC REVIEW ONLY"
        html = """<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
<title>Private cashflow review</title><style>
body{font:15px/1.5 system-ui,sans-serif;color:#172435;background:#f4f6f8;margin:24px}
main{max-width:1500px;margin:auto}section{background:white;padding:20px;margin:24px 0;border:1px solid #ccd5df;border-radius:8px}
h1{font-size:28px}h2{font-size:21px}p{max-width:1000px}.scroll{overflow:auto;max-height:650px}
nav{display:flex;gap:16px;flex-wrap:wrap;padding:16px;background:white}a{color:#164e9a}section:target{outline:3px solid #3376c4}
table{border-collapse:collapse;width:100%;font-size:13px}th,td{padding:9px;border:1px solid #d9dfe7;text-align:left;vertical-align:top;white-space:nowrap}
th{position:sticky;top:0;background:#e9eff6}tr:nth-child(even){background:#f8fafc}.gate{font-weight:bold;background:#fff2c9;padding:12px}
@media print{.scroll{max-height:none;overflow:visible}body{margin:0}th{position:static}}
</style><main>"""
        html += f"<h1>Private cashflow review: {start:%B %Y}</h1><p class='gate'>{readiness}</p>"
        html += '<nav aria-label="Review queues"><a href="#uncategorized">Uncategorized transactions</a><a href="#unpaired">Unpaired transfers/payments</a><a href="#unmatched-refunds">Unmatched refund candidates</a></nav>'
        html += f"<p>Generated {datetime.now(timezone.utc).isoformat()}. Review period: {start} through {end - timedelta(days=1)}. Stored locally; not published or emailed.</p>"
        html += "<p>Review in order: accounts and coverage → bank transaction comparison → income/refunds → excluded transfers → categories → recurring and outlier candidates. Keep notes privately. A passing pipeline does not establish that its business rules match your intentions.</p>"
        html += "".join(sections) + "</main></html>"
        output = ROOT / ".local" / "review" / f"cashflow-review-{start:%Y-%m}.html"
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(html, encoding="utf-8")
        return output
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--month", help="Calendar month, YYYY-MM; default is month before the cutoff")
    args = parser.parse_args()
    try:
        output = generate(args.database, args.month)
    except Exception as error:
        # Database exceptions can include data values; do not print them.
        raise SystemExit(f"Review generation failed ({type(error).__name__}); no transaction data logged.") from None
    print(f"Private review saved to {output}")


if __name__ == "__main__":
    main()
