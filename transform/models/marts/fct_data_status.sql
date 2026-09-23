with coverage as (
    select
        expected.institution,
        expected.account_type,
        expected.expected_count,
        count(accounts.account_id) as actual_count
    from {{ ref('expected_accounts') }} as expected
    full outer join {{ ref('fct_account_status') }} as accounts
        on expected.institution = accounts.institution
        and expected.account_type = accounts.account_type
    group by expected.institution, expected.account_type, expected.expected_count
),

summary as (
    select
        count(*) as account_count,
        count(*) filter (where freshness_status = 'ready') as ready_account_count,
        min(imported_through_date) as earliest_coverage_date,
        min(last_synced_at) as oldest_account_sync_at,
        max(last_synced_at) as source_refresh_time,
        max(latest_transaction_date) as latest_transaction_date
    from {{ ref('fct_account_status') }}
),

quality as (
    select
        count(*) filter (
            where pipeline_reconciliation_status != 'passed'
        ) as reconciliation_failures,
        coalesce(sum(uncategorized_count), 0) as uncategorized_count,
        coalesce(sum(unmatched_transfer_count), 0) as unmatched_transfer_count,
        coalesce(sum(unmatched_refund_count), 0) as unmatched_refund_count
    from {{ ref('fct_account_reconciliation') }}
),

readiness as (
    select summary.*, quality.*,
        not exists (
            select 1 from coverage
            where actual_count is distinct from expected_count
        ) and account_count > 0 as account_coverage_complete
    from summary cross join quality
)

select *,
    account_coverage_complete and ready_account_count = account_count
        and reconciliation_failures = 0 as ready_for_reporting,
    case when account_coverage_complete and ready_account_count = account_count
        and reconciliation_failures = 0 then earliest_coverage_date
    end as data_cutoff_date,
    'USD' as currency,
    'America/New_York' as reporting_timezone
from readiness
