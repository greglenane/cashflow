{% if target.name == 'prod' %}
    {% set input_relation = ref('int_plaid_current_transactions') %}
{% else %}
    {% set input_relation = ref('plaid_transactions') %}
{% endif %}

with source_ranked as (
    select *, row_number() over (
        partition by transaction_id order by imported_at desc, source_file desc
    ) as source_rank
    from {{ input_relation }}
),

source_totals as (
    select
        account_id,
        count(*) filter (where source_rank > 1) as duplicate_record_count,
        count(*) filter (where source_rank = 1 and pending) as pending_count,
        count(*) filter (where source_rank = 1 and not pending) as source_posted_count,
        coalesce(sum(-cast(plaid_amount as decimal(18, 2))) filter (
            where source_rank = 1 and not pending
        ), 0) as source_posted_amount
    from source_ranked
    group by account_id
),

canonical_totals as (
    select
        account_id,
        count(*) as canonical_count,
        sum(amount) as canonical_amount,
        count(*) filter (where category = 'Uncategorized') as uncategorized_count,
        count(*) filter (
            where flow_type in ('transfer', 'card_payment')
                and transfer_match_id is null
        ) as unmatched_transfer_count,
        count(*) filter (where refund_status = 'unmatched') as unmatched_refund_count
    from {{ ref('fct_transactions') }}
    group by account_id
),

compared as (
    select
        accounts.account_id,
        coalesce(source_totals.duplicate_record_count, 0) as duplicate_record_count,
        coalesce(source_totals.pending_count, 0) as pending_count,
        coalesce(source_totals.source_posted_count, 0) as source_posted_count,
        coalesce(source_totals.source_posted_amount, 0) as source_posted_amount,
        coalesce(canonical_totals.canonical_count, 0) as canonical_count,
        coalesce(canonical_totals.canonical_amount, 0) as canonical_amount,
        coalesce(canonical_totals.uncategorized_count, 0) as uncategorized_count,
        coalesce(canonical_totals.unmatched_transfer_count, 0) as unmatched_transfer_count,
        coalesce(canonical_totals.unmatched_refund_count, 0) as unmatched_refund_count
    from {{ ref('stg_plaid_accounts') }} as accounts
    left join source_totals using (account_id)
    left join canonical_totals using (account_id)
)

select *,
    canonical_count - source_posted_count as count_difference,
    canonical_amount - source_posted_amount as amount_difference,
    case when canonical_count = source_posted_count
        and canonical_amount = source_posted_amount then 'passed'
        else 'failed'
    end as pipeline_reconciliation_status,
    'not_available' as statement_reconciliation_status
from compared
