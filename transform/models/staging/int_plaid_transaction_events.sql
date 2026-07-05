{{ config(
    enabled=target.name == 'prod',
    materialized='table'
) }}

with batch_metadata as (
    select
        source_file,
        batch,
        json_extract_string(batch, '$.institution') as institution,
        json_extract_string(batch, '$.batch_id') as batch_id,
        cast(json_extract_string(batch, '$.fetched_at') as timestamptz) as fetched_at
    from {{ ref('int_plaid_raw_batches') }}
),

added as (
    select
        source_file,
        institution,
        batch_id,
        fetched_at,
        'added' as event_type,
        unnest(
            cast(json_extract(batch, '$.added') as json[])
        ) as transaction_json
    from batch_metadata
),

modified as (
    select
        source_file,
        institution,
        batch_id,
        fetched_at,
        'modified' as event_type,
        unnest(
            cast(json_extract(batch, '$.modified') as json[])
        ) as transaction_json
    from batch_metadata
),

removed as (
    select
        source_file,
        institution,
        batch_id,
        fetched_at,
        'removed' as event_type,
        unnest(
            cast(json_extract(batch, '$.removed') as json[])
        ) as transaction_json
    from batch_metadata
)

select * from added
union all
select * from modified
union all
select * from removed
