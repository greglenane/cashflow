{{ config(
    enabled=target.name == 'prod',
    materialized='table'
) }}

with extracted as (
    select
        json_extract_string(transaction_json, '$.transaction_id') as transaction_id,
        json_extract_string(transaction_json, '$.account_id') as account_id,
        cast(json_extract_string(transaction_json, '$.date') as date) as transaction_date,
        json_extract_string(transaction_json, '$.name') as name,
        json_extract_string(transaction_json, '$.merchant_name') as merchant_name,
        cast(json_extract_string(transaction_json, '$.amount') as decimal(18, 2)) as plaid_amount,
        json_extract_string(
            transaction_json,
            '$.personal_finance_category.primary'
        ) as personal_finance_category_primary,
        json_extract_string(
            transaction_json,
            '$.personal_finance_category.detailed'
        ) as personal_finance_category_detailed,
        coalesce(
            cast(json_extract_string(transaction_json, '$.pending') as boolean),
            false
        ) as pending,
        source_file,
        fetched_at as imported_at,
        event_type,
        batch_id
    from {{ ref('int_plaid_transaction_events') }}
),

latest as (
    select *,
        row_number() over (
            partition by transaction_id
            order by imported_at desc, batch_id desc
        ) as event_rank
    from extracted
    where transaction_id is not null
)

select
    transaction_id,
    account_id,
    transaction_date,
    name,
    merchant_name,
    plaid_amount,
    personal_finance_category_primary,
    personal_finance_category_detailed,
    pending,
    source_file,
    imported_at
from latest
where event_rank = 1
  and event_type != 'removed'
