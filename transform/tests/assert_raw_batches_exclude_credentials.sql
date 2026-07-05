{{ config(enabled=target.name == 'prod') }}

select source_file
from {{ ref('int_plaid_raw_batches') }}
where json_extract(batch, '$.access_token') is not null
   or json_extract(batch, '$.item_id') is not null
   or json_extract(batch, '$.PLAID_CLIENT_ID') is not null
   or json_extract(batch, '$.PLAID_SECRET') is not null
