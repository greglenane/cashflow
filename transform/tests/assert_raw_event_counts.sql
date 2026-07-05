{{ config(enabled=target.name == 'prod') }}

with expected as (
    select
        coalesce(sum(json_array_length(batch, '$.added')), 0)
        + coalesce(sum(json_array_length(batch, '$.modified')), 0)
        + coalesce(sum(json_array_length(batch, '$.removed')), 0)
            as event_count
    from {{ ref('int_plaid_raw_batches') }}
),

actual as (
    select count(*) as event_count
    from {{ ref('int_plaid_transaction_events') }}
)

select
    expected.event_count as expected_count,
    actual.event_count as actual_count
from expected
cross join actual
where expected.event_count != actual.event_count
