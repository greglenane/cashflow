with activity as (
    select account_id, max(transaction_date) as latest_transaction_date
    from {{ ref('fct_transactions') }}
    group by account_id
),

status as (
    select
        accounts.*,
        activity.latest_transaction_date,
        sync.last_synced_at,
        sync.update_status,
        case when sync.update_status = 'HISTORICAL_UPDATE_COMPLETE'
            then cast(timezone('America/New_York', sync.last_synced_at) as date) - 1
        end as imported_through_date,
        {% if target.name == 'dev' %}
        cast('{{ var("reporting_as_of_date", "2026-07-04") }}' as date)
        {% else %}
        cast(timezone('America/New_York',
            cast('{{ run_started_at.isoformat() }}' as timestamptz)) as date)
        {% endif %}
            as reporting_as_of_date
    from {{ ref('stg_plaid_accounts') }} as accounts
    left join activity using (account_id)
    left join {{ ref('stg_plaid_sync_status') }} as sync
        on accounts.account_id = sync.account_id
        and accounts.institution = sync.institution
)

select *,
    case
        when last_synced_at is null then 'missing_sync'
        when update_status is distinct from 'HISTORICAL_UPDATE_COMPLETE'
            then 'incomplete_history'
        when imported_through_date >= reporting_as_of_date then 'future_sync'
        when imported_through_date < reporting_as_of_date - 1 then 'stale'
        else 'ready'
    end as freshness_status
from status
