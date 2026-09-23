# Reviewing the analytics against your intentions

Automated tests establish that the code follows its rules. They cannot establish
that Plaid labels, refund assumptions, or the definition of spending match what
you want. Review those separately before using the dashboard to draw conclusions.

## What the current pipeline does

1. Incrementally syncs the existing Wells Fargo and Amex Plaid Items. Raw batches
   contain added, modified, and removed events. Existing cursor state is retained.
   This collects changes already available from Plaid; it does not force a fresh
   bank scrape, guarantee two years of history, or reconnect accounts.
2. Replays those events into the current transaction state, takes the latest
   version per transaction ID, and excludes pending transactions. Transactions
   with different IDs are not deduplicated merely because amounts/dates match.
3. Converts Plaid's positive-outflow convention into negative purchases and
   positive receipts. The merchant is Plaid's merchant name, falling back to the
   description; there is no general merchant-alias dictionary yet.
4. Applies classifications in this order: explicit card-payment labels (including
   Plaid's `LOAN_PAYMENTS_CREDIT_CARD_PAYMENT` for either sign);
   other transfer labels; positive amounts with an INCOME label; other positive
   amounts as refund candidates; negative amounts as expenses; zero as excluded.
5. Maps Plaid's broad categories to display names. Merchant regex overrides can
   change expense/refund categories; lower priority numbers win, with rule ID
   breaking ties. Quincy Market is explicitly classified as Food & Drink per
   the user's direction; there is also a synthetic fixture rule.
   These overrides do not currently change income/transfer/expense flow types.
6. Pairs transactions already labeled transfers/payments if their amounts are
   equal and opposite, accounts differ, and posted dates are within three days.
   Both sides must select one another as their best candidate. Unmatched
   transfers/payments remain excluded and are surfaced for review.
7. Matches a full refund only when one purchase and one refund uniquely match
   on account, case/whitespace-insensitive merchant, absolute amount, and a
   0–180-day date interval. The refund reduces the original purchase period and
   category. Partial or ambiguous refunds remain separate. Fully refunded
   purchases are omitted from recurring and outlier detection.
8. Computes income, net spending, net cashflow (income minus net spending), and
   savings rate (null with zero income). These are spending-based analytics,
   not checking-account balance changes: a credit purchase counts when posted,
   not when its bill is paid, and matched refunds restate earlier periods.
9. Checks expected account coverage, completed sync status, and source-to-fact
   counts/amounts. Estimated coverage ends on the prior New York calendar day
   at the latest completed sync. All three accounts must be current. This is not
   a bank-certified posting cutoff or a reconciliation to statement balances.
10. Compares month-to-date through that cutoff against the same day numbers in
    the previous month and previous year, capped at shorter month ends. Empty
    comparison windows currently appear as zero; the model does not yet prove
    that the bank supplied the full history for each comparison window.

Monthly history uses all loaded transactions; the MTD comparison has its explicit
cutoff. Thus a posted transaction from today can appear in monthly history but
not yet in the MTD comparison. Dates shown beside the metrics matter.

## Detection rules to inspect

Recurring candidates group expenses by merchant and category across accounts
and all loaded history. They need at least three occurrences. Median intervals
of 5–9, 25–35, 80–100, and 350–380 days map to weekly, monthly, quarterly, and
annual cadence. At least 75% of amounts must be within 20% of the median, and at
least 75% of intervals must be within the cadence tolerance of the median
interval (2, 5, 10, or 30 days). The next date is the last date plus the rounded
median interval. Confidence is a heuristic, not a calibrated probability.
There is no cancellation/active-subscription check; old or routine purchases can
qualify. Monthly-equivalent cost is not automatically a current subscription bill.

Outliers use the category's entire loaded expense history, including the candidate
purchase, to compute median and median absolute deviation (MAD). With at least
five purchases, a flag requires at least $250, at least three times the median,
and a modified z-score of at least 5. If MAD is zero, the first two thresholds
apply. With fewer than five purchases, the absolute threshold is $1,000. A flag
means unusual under this rule, not incorrect, fraudulent, or unnecessary.

## Manual review sequence

Use the last completed calendar month first, then check the current comparable
period. Keep bank statements open privately; do not paste transaction details
into project documentation or chat.

1. Confirm that the three masked account labels are the intended accounts and
   examine earliest/latest transaction dates. A successful sync does not prove
   complete historical coverage.
2. For each account, compare posted transaction dates, amounts, and counts to
   the bank over the same calendar dates. Card statements often use a different
   cycle; compare individual records or deliberately select matching dates.
3. Check every income entry and positive refund candidate. Focus on payroll,
   reimbursements, peer-to-peer payments, rewards, interest, and returned payments.
4. Check every excluded transfer/card payment. Confirm both sides where available.
   Transfers to accounts outside this project need a deliberate interpretation.
5. Check refunds: whether they belong to a purchase, whether partial refunds should
   reduce spending, and whether you prefer refund-date or purchase-date allocation.
6. Check expense categories and flag merchants requiring aliases or overrides.
7. Add the transaction contribution columns: income_amount, spending_amount,
   unmatched_refund_amount. Confirm income minus spending and compare with the
   shared monthly model. The report includes posted-date rows and reporting-date
   contributors separately so cross-month refunds are visible.
8. Inspect recurring candidates for actual recurring obligations and canceled
   services. Inspect large unflagged purchases as well as flagged outliers to
   evaluate missed cases, not just false positives.

Record desired rule changes separately from data errors. For example, “this
reimbursement should offset dining” is a policy decision; “this posted amount
differs from the bank” is an ingestion/reconciliation issue.

## Private review report

After a successful production dbt build, from the repository root:

```bash
uv run python tools/analytics-review/review.py --database .local/cashflow-prod.duckdb
# Optional calendar month:
uv run python tools/analytics-review/review.py --database .local/cashflow-prod.duckdb --month 2026-08
```

The standalone report is written under ignored `.local/review/` and contains
private data. It uses the shared models, opens the database read-only, and makes
no network calls. Open it locally in a browser. Nothing is published or emailed.
Read the reporting gate before using its totals; a blocked dataset can still be
inspected for diagnosis but is not approved for reporting.
