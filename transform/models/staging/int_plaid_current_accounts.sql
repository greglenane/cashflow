{{ config(
    enabled=target.name == 'prod',
    materialized='table'
) }}

with account_events as (
    select
        json_extract_string(account.value, '$.account_id') as account_id,
        json_extract_string(batch, '$.institution') as institution,
        json_extract_string(account.value, '$.type') as plaid_account_type,
        json_extract_string(account.value, '$.subtype') as plaid_account_subtype,
        json_extract_string(account.value, '$.mask') as mask,
        json_extract_string(account.value, '$.name') as plaid_account_name,
        cast(json_extract_string(batch, '$.fetched_at') as timestamptz) as fetched_at,
        json_extract_string(batch, '$.batch_id') as batch_id
    from {{ ref('int_plaid_raw_batches') }},
    lateral json_each(json_extract(batch, '$.accounts')) as account
    where json_type(json_extract(batch, '$.accounts')) = 'ARRAY'
),

latest as (
    select *,
        row_number() over (
            partition by account_id
            order by fetched_at desc, batch_id desc
        ) as event_rank
    from account_events
),

normalized as (
    select
        account_id,
        institution,
        case
            when plaid_account_type = 'depository'
                and plaid_account_subtype = 'checking' then 'checking'
            when plaid_account_type = 'credit' then 'credit'
            else plaid_account_type
        end as account_type,
        case
            when institution = 'wells-fargo'
                and plaid_account_type = 'depository' then 'WF Checking'
            when institution = 'wells-fargo'
                and plaid_account_type = 'credit' then 'WF Credit'
            when institution = 'amex' then 'Amex Credit'
            else coalesce(plaid_account_name, institution)
        end as account_label,
        mask
    from latest
    where event_rank = 1
)

select
    account_id,
    case
        when mask is not null then account_label || ' ••' || mask
        else account_label
    end as account_name,
    account_type,
    institution
from normalized
