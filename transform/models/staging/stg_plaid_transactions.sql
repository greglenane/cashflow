{% if target.name == 'prod' %}
    {% set transaction_relation = ref('int_plaid_current_transactions') %}
{% else %}
    {% set transaction_relation = ref('plaid_transactions') %}
{% endif %}

with typed as (
    select
        cast(transaction_id as varchar) as transaction_id,
        cast(account_id as varchar) as account_id,
        cast(transaction_date as date) as transaction_date,
        cast(name as varchar) as description_raw,
        coalesce(nullif(cast(merchant_name as varchar), ''), cast(name as varchar)) as merchant_normalized,
        -1 * cast(plaid_amount as decimal(18, 2)) as amount,
        cast(personal_finance_category_primary as varchar) as category_primary,
        cast(personal_finance_category_detailed as varchar) as category_detailed,
        cast(pending as boolean) as pending,
        cast(source_file as varchar) as source_file,
        cast(imported_at as timestamptz) as imported_at
    from {{ transaction_relation }}
),

deduplicated as (
    select *,
        row_number() over (
            partition by transaction_id
            order by imported_at desc, source_file desc
        ) as duplicate_rank
    from typed
)

select * exclude (duplicate_rank)
from deduplicated
where duplicate_rank = 1
  and not pending
