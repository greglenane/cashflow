# Manually checked synthetic period

All amounts below are synthetic USD. Reporting timezone: America/New_York.
The fixture's reporting date is July 4, 2026; both institution syncs completed
that morning, giving a shared July 3 cutoff.

## July 1–3, 2026

| Contribution | Amount |
| --- | ---: |
| Grocery expense | 125.50 |
| Hardware expense | 80.00 |
| Cafe expense | 65.00 |
| Streaming expense | 20.00 |
| **Spending** | **290.50** |
| Income | 0.00 |
| **Net cashflow** | **-290.50** |
| Unmatched partial cafe refund, shown separately | 20.00 |

Savings rate is null because income is zero. The $500 checking payment and
matching $500 credit-card receipt are excluded. The pending $15 purchase is
excluded. The repeated $125.50 grocery source row contributes only once. The
$20 cafe refund does not fully match the $65 purchase and is not automatically
netted into spending.

June 1–3 spending is $100 + $20 = **$120**; July spending is **$170.50 higher**
(142.0833%). July 1–3, 2025 spending is **$200**; current spending is **$90.50
higher** (45.25%). June's $2,500 payroll is dated June 30 and is outside the
prior-month comparison window.

## Full June 2026

Income is **$2,500**, spending is **$120**, net cashflow is **$2,380**, and savings
rate is **95.2%**. These fixed expectations are checked independently of the SQL
aggregation implementation.

## Source reconciliation

The fixture contains **19 source rows**. Dropping one older duplicate version
and one pending transaction produces **17 canonical rows**. All three accounts
have zero differences in posted record counts and signed amounts between source
and canonical records. This is pipeline reconciliation, not a comparison against
bank statement balances.

## Full-refund scenario

A separate test supplies an $80 purchase on June 28 and a matching $80 refund on
July 3. Both retain their original posted dates and IDs. The refund's reporting
date becomes June 28 and its reporting category comes from the purchase, reducing
June spending by $80. July receives no spending reduction for that matched
refund. Partial, ambiguous, duplicate, too-old, and cross-account matches are
rejected in the same test.

## Display requirements for the next milestone

Evidence and the report must show the cutoff and account sync timestamps, label
unmatched refunds separately, and explain that matched refunds restate the
purchase period. They must not describe pipeline reconciliation as bank-statement
reconciliation or estimated import coverage as guaranteed posting completeness.
