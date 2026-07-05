{{ config(enabled=target.name == 'dev') }}

select count(*) as actual_rows
from {{ ref('fct_transactions') }}
having count(*) != 17
