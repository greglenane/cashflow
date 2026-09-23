-- A zero-change batch is still evidence of a completed sync. Transaction dates
-- alone cannot establish coverage for an account with no recent purchases.
{% if target.name == 'prod' %}
with batches as (
    select
        json_extract_string(batch, '$.institution') as institution,
        json_extract_string(batch, '$.batch_id') as batch_id,
        cast(json_extract_string(batch, '$.fetched_at') as timestamptz) as fetched_at,
        json_extract_string(batch, '$.transactions_update_status') as update_status,
        batch
    from {{ ref('int_plaid_raw_batches') }}
),

latest as (
    select * from batches
    qualify row_number() over (
        partition by institution order by fetched_at desc, batch_id desc
    ) = 1
)

select
    latest.institution,
    json_extract_string(account.value, '$.account_id') as account_id,
    latest.fetched_at as last_synced_at,
    latest.update_status
from latest,
lateral json_each(json_extract(batch, '$.accounts')) as account
{% else %}
select
    cast(institution as varchar) as institution,
    cast(account_id as varchar) as account_id,
    cast(last_synced_at as timestamptz) as last_synced_at,
    cast(update_status as varchar) as update_status
from {{ ref('plaid_sync_status') }}
{% endif %}
