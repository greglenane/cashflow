{{ config(
    enabled=target.name == 'prod',
    materialized='table'
) }}

select
    filename as source_file,
    cast(content as json) as batch
from read_text(
    's3://cashflow-dashboard/raw/plaid/*/*/*/*/*.json'
)
