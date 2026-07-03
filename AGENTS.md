# Cashflow Dashboard Project

## Goal

Build a private cashflow dashboard with [Evidence](https://evidence.dev/) that combines transactions from:

1. Wells Fargo checking
2. Wells Fargo credit card
3. American Express credit card

The dashboard must help answer:

- How does income compare with spending?
- Which purchases are recurring?
- Which purchases are unusual or outliers?
- How is spending changing month over month?
- How does spending in the current month compare with the same month one year ago?

The Evidence site will be built and hosted with GitHub Pages. A scheduled GitHub Actions workflow will refresh the data, rebuild and deploy the site, and email a daily HTML/PDF cashflow summary at approximately 5:00 AM America/New_York.

## Working Principles

- Treat financial data as sensitive. Never commit credentials, account numbers, raw statements, or unredacted exports.
- Use read-only data access wherever an account integration supports it.
- Keep secrets in ignored environment files or the deployment platform's secret store.
- Normalize source data before building dashboard metrics. Do not embed source-specific cleanup rules in page queries.
- Make calculations reproducible and explainable. A user must be able to drill from a metric to its contributing transactions.
- Prefer simple SQL and Evidence-native components over unnecessary application code.
- Preserve source records and make ingestion idempotent so repeated imports do not duplicate transactions.
- Prefer DuckDB, private S3 buckets, dbt, and Evidence for the data and reporting stack.

## Initial Scope

### In scope

- Import transaction data from the three named accounts through Plaid Transactions.
- Keep CSV exports as a manual fallback when Plaid connectivity is unavailable.
- Normalize transactions into a shared model.
- Categorize income and spending, with user-overridable rules.
- Identify transfers and credit-card payments so they are not counted as spending or income.
- Provide monthly summary metrics and transaction-level drill-downs.
- Detect likely recurring and outlier purchases.
- Show data freshness and account reconciliation status.
- Build and deploy the static Evidence site to GitHub Pages.
- Run an automated daily refresh, validation, build, deployment, and report-delivery workflow.
- Generate and email a daily HTML report with a matching PDF attachment.

### Out of scope unless requested

- Moving money, paying bills, or writing back to financial institutions.
- Budget enforcement or investment tracking.
- Tax, accounting, or financial advice.
- Multi-user authentication beyond what is required to deploy the private dashboard.

## Infrastructure and Data Architecture

Use the following responsibilities:

- **S3-compatible object storage:** Durable system of record for encrypted source imports and approved derived datasets. Use separate prefixes or buckets for `raw`, `staging`, `curated`, and temporary report output.
- **DuckDB:** Local analytical engine used by ingestion, dbt, validation, and report generation. Query Parquet data in S3 where practical. Do not treat a shared DuckDB file in S3 as a transactional or concurrently writable database.
- **dbt:** Own normalization, deduplication, categorization, transfer matching, tests, and analytics-ready models. Prefer `dbt-duckdb` unless a concrete limitation requires another adapter.
- **Evidence:** Read only curated, analytics-ready models. Own dashboard queries, components, and static-site generation, but not source-specific cleanup or core financial definitions.
- **GitHub Actions:** Orchestrate the daily import, dbt build/test, Evidence build, report rendering, S3 publication, GitHub Pages deployment, and email delivery.

Confirmed AWS resources:

- Region: `us-east-1`
- Private S3 bucket: `cashflow-dashboard`
- Plaid credential secret: `cashflow/plaid/production`
- Plaid Wells Fargo Item secret: `cashflow/plaid/items/wells-fargo`
- Plaid American Express Item secret: `cashflow/plaid/items/amex`
- Local/MCP AWS profile: `cashflow-mcp` with non-root, metadata-only access
- Local Plaid linker profile: `cashflow-linker`, which assumes `CashflowPlaidLinker` and must never be exposed to MCP
- Local Plaid sync profile: `cashflow-sync`, which assumes `CashflowPlaidSync` and must never be exposed to MCP

Target data flow:

`Financial exports/integrations -> private S3 raw zone -> DuckDB/dbt models -> private S3 curated Parquet -> Evidence and daily report -> GitHub Pages/email`

Architecture requirements:

- Keep raw and curated S3 objects private with public access blocked, encryption enabled, and narrowly scoped IAM permissions.
- Never use AWS root credentials for local development, MCP access, application code, or GitHub Actions. Use separate least-privilege roles for local/MCP infrastructure work and the production workflow.
- MCP infrastructure access must not include `secretsmanager:GetSecretValue` unless a narrowly scoped, explicitly approved task requires it.
- Enable S3 versioning and lifecycle rules appropriate to the sensitivity and required retention of each zone.
- Partition curated Parquet by a useful low-cardinality date boundary such as year/month; avoid excessive small files.
- Use deterministic object keys and import batch metadata so reruns are idempotent and auditable.
- Keep the ephemeral DuckDB database and temporary report files on the workflow runner; do not upload them unless required.
- Expose only the minimum aggregated or redacted dataset needed for the Evidence build.
- Use one dbt model as the canonical transaction fact table and shared downstream models for dashboard and email metrics.
- Put dbt model contracts, tests, and documentation beside the transformations they validate.
- Pin and regularly review versions of DuckDB, dbt, the DuckDB dbt adapter, Evidence, and GitHub Actions.
- Estimate S3 request, storage, email-provider, and GitHub Actions costs before enabling daily automation.

## Canonical Data Model

Create a normalized transaction table or model with at least:

| Field | Purpose |
| --- | --- |
| `transaction_id` | Stable deduplication key |
| `account_id` | Internal non-sensitive account identifier |
| `account_name` | Checking, Wells Fargo credit, or Amex credit |
| `account_type` | `checking` or `credit` |
| `transaction_date` | Posted transaction date |
| `description_raw` | Original source description |
| `merchant_normalized` | Clean merchant name used for grouping |
| `amount` | Signed canonical amount |
| `flow_type` | `income`, `expense`, `transfer`, `card_payment`, `refund`, or `excluded` |
| `category` | User-facing spending category |
| `source` | Import source and format |
| `source_file` | Import batch identifier, not a sensitive absolute path |
| `imported_at` | Ingestion timestamp |

Canonical sign convention:

- Positive amounts increase cash/net position, such as income and refunds.
- Negative amounts decrease cash/net position, such as purchases.
- Credit-card source signs must be converted to this convention during normalization.

Keep account metadata in a separate model. Store only masked labels such as `WF Checking ••1234` when a suffix is needed for reconciliation.

## Metric Definitions

Use these definitions consistently:

- **Income:** Sum of positive transactions classified as `income`.
- **Spending:** Absolute value of negative transactions classified as `expense`.
- **Net cashflow:** Income minus spending.
- **Savings rate:** Net cashflow divided by income; return null when income is zero.
- **Month-over-month change:** Current comparable period spending versus the immediately preceding comparable period.
- **Year-over-year change:** Current comparable period spending versus the same calendar period one year earlier.

For current-month comparisons, compare through the latest fully imported transaction date, not a partial month against a complete prior month. Display the comparison cutoff date.

Exclude transfers, credit-card payments, reversals, and duplicates from income and spending totals. Refunds should reduce spending in the category and period to which they belong when matching is reliable; otherwise show them separately and document the treatment.

## Detection Rules

### Recurring purchases

Start with an explainable heuristic:

- Group by normalized merchant and, where useful, category.
- Require at least three occurrences.
- Detect weekly, monthly, quarterly, or annual cadence using date intervals with a reasonable tolerance.
- Require amounts to be identical or within a configurable variance.
- Report confidence, expected cadence, typical amount, last charge, and predicted next charge.

Do not label transfers, card payments, or ordinary high-frequency merchants as subscriptions without enough evidence.

### Outlier purchases

Detect outliers only among expenses. Use robust statistics such as median and median absolute deviation within a category or merchant cohort. Also surface unusually large absolute purchases when a cohort has too little history.

Every outlier must show why it was flagged, including the comparison baseline. Avoid opaque anomaly scores as the only explanation.

## Dashboard Pages

1. **Overview**
   - Income, spending, net cashflow, and savings rate
   - Current month-to-date with prior-month and prior-year comparable periods
   - Monthly income and spending trend
   - Account/data freshness status
2. **Spending**
   - Month-over-month trends
   - Category and merchant breakdowns
   - Filters for date, account, category, and merchant
   - Transaction drill-down
3. **Recurring**
   - Likely recurring purchases and subscriptions
   - Monthly equivalent cost
   - Confidence and cadence details
4. **Outliers**
   - Flagged transactions ranked by materiality
   - Reason and baseline for each flag
5. **Data Quality**
   - Import history, duplicate counts, uncategorized transactions, and reconciliation checks

## Hosting and Daily Automation

- Host the built Evidence site with GitHub Pages.
- Use GitHub Actions for the full daily pipeline: ingest, normalize, validate, build, deploy, render the report, and send email.
- Target approximately 5:00 AM in the `America/New_York` timezone. Account for daylight-saving time explicitly; GitHub Actions cron schedules are UTC and may start later than scheduled.
- Make the workflow safe to retry and prevent overlapping daily runs with a concurrency group.
- Fail before deployment or email delivery when ingestion, reconciliation, tests, or the Evidence build fails.
- Show the source-data cutoff and successful refresh time in both the dashboard and report.
- Keep credentials, recipient addresses, provider tokens, and account-integration secrets in GitHub Actions secrets or environments.
- Do not commit refreshed financial data, generated reports, or build output containing private data to the repository.
- Use least-privilege workflow permissions and pin third-party actions to immutable commit SHAs.

GitHub Pages publishes static files that can contain data embedded during the Evidence build. Treat the generated site as sensitive. Before enabling deployment with real data, confirm that the selected GitHub plan and Pages configuration provide the required access control. If they do not, publish only sufficiently aggregated and redacted data or use a private hosting option. A private source repository alone must not be assumed to make the Pages site private.

## Daily Email Report

Generate one report from shared SQL models, then use it for both the HTML email and PDF attachment so their values cannot drift.

The report should include:

- **Data status:** latest transaction date, refresh time, covered accounts, and any quality warnings.
- **Very recent activity:** prior-day and trailing-seven-day income, spending, net cashflow, notable transactions, new outliers, and newly detected or changed recurring purchases.
- **Current month:** month-to-date income, spending, net cashflow, savings rate, and top categories and merchants.
- **Comparable trends:** month-to-date versus the same number of days in the prior month and the same month one year earlier.
- **Macro trends:** monthly income, spending, and net cashflow; trailing 3-, 6-, and 12-month averages; category shifts; recurring-cost trend; and the rolling 12-month savings rate.

Report requirements:

- Put the reporting period, comparison cutoff, currency, and timezone beside the headline metrics.
- Keep the email concise and link to the relevant dashboard views for drill-down.
- Explain material changes and anomaly flags with their contributing amounts rather than presenting unsupported conclusions.
- Send no email when validation fails; send a failure notification that contains diagnostics but no transaction data.
- Do not store reports as long-lived public workflow artifacts. If temporary artifacts are required between jobs, minimize retention and treat them as sensitive.
- Prevent duplicate daily emails when a workflow is retried by recording or deriving a stable report date/idempotency key.
- Use an email provider or SMTP account approved by the user, with credentials stored only in GitHub secrets.

## Implementation Order

1. Scaffold the Evidence and dbt projects and document local commands.
2. Add `.gitignore` coverage for secrets, local exports, DuckDB files, generated data, reports, and Evidence build artifacts.
3. Define the private S3 zones, object naming, retention, encryption, and least-privilege IAM policy.
4. Create fixture data with synthetic transactions for all three accounts.
5. Implement source-specific ingestion into the S3 raw zone.
6. Implement dbt/DuckDB normalization and publish curated Parquet models.
7. Add deduplication, transfer/card-payment matching, categorization, reconciliation, and dbt tests.
8. Build shared dbt models for monthly metrics, recurring purchases, and outliers.
9. Build the Evidence dashboard pages and drill-downs from curated models.
10. Build the shared HTML/PDF daily report from the same models.
11. Validate calculations against a small manually checked period.
12. Add the DST-aware daily GitHub Actions workflow and safe refresh procedure.
13. Configure S3, GitHub Pages deployment, and email delivery after the privacy model and providers are approved.

## Definition of Done

- All three accounts are represented and their latest import dates are visible.
- Raw and curated datasets are stored in private, encrypted S3 locations with least-privilege access.
- DuckDB and dbt can reproduce all curated models from source imports.
- Evidence and the email report consume shared curated models rather than independently calculating core metrics.
- Re-importing the same source data creates no duplicates.
- Credit-card payments and inter-account transfers are not double-counted.
- Overview totals reconcile to normalized transaction records.
- Current-month comparisons use matching day cutoffs.
- Recurring and outlier results include understandable reasons.
- Filters and transaction drill-downs work across all headline metrics.
- The site deploys successfully to the configured GitHub Pages environment.
- The scheduled workflow targets approximately 5:00 AM America/New_York and handles daylight-saving changes.
- The HTML email and PDF attachment reconcile to dashboard metrics and are sent at most once per reporting date.
- Workflow failures do not deploy stale/invalid results or email sensitive partial output.
- Automated tests cover sign normalization, deduplication, exclusions, period comparisons, and detection edge cases.
- No secrets or sensitive raw financial files are tracked by Git.

## Agent Guidance

- Inspect existing files and preserve user changes before editing.
- Prefer Git Bash syntax for terminal instructions and local commands. Use PowerShell only for Windows-specific operations that do not have a reliable Git Bash equivalent.
- Use AWS CLI v2 with named profiles and temporary credentials; do not create long-lived IAM access keys for this project.
- Use the installed `aws-core` plugin for AWS guidance.
- For every AWS operation, explicitly use the `cashflow-mcp` profile and `us-east-1` Region. Do not rely on an inherited or default AWS identity.
- Never retrieve Plaid secret values through MCP.
- Use `tools/plaid-linker` locally to create or repair Plaid Items. Export temporary `cashflow-linker` credentials only into the terminal running that utility, and never log or return Plaid access tokens.
- Use `tools/plaid-sync` for incremental Plaid ingestion. Export temporary `cashflow-sync` credentials only into the terminal running that utility. Write immutable raw batches before advancing S3 cursor state, and never log transactions, access tokens, or cursors.
- Keep source-specific transformations isolated from shared analytics models.
- Keep orchestration logic thin; business logic belongs in tested dbt models.
- Do not persist credentials in DuckDB files, dbt profiles, Evidence source configuration, logs, or generated artifacts.
- Add or update tests with every change to financial calculations.
- Use synthetic fixtures in the repository; never copy real transaction details into tests or documentation.
- When a financial definition is ambiguous, document the assumption in the dashboard and this file.
- Do not connect to a live financial account, add a paid provider, configure an email recipient, or upload private data without explicit user approval.
- Do not enable GitHub Pages with real financial data until its access-control and redaction strategy has been explicitly confirmed.
- Before handing off a change, run the relevant formatting, validation, tests, and Evidence build; report any command that could not be run.
