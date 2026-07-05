{{ config(enabled=target.name == 'dev') }}

select count(*) as unexpected_result_count
from {{ ref('fct_outlier_purchases') }}
having count(*) != 1
    or count(*) filter (
        where transaction_id = 'txn_store_outlier'
          and category = 'Shopping'
          and amount_absolute = 500.00
          and category_transaction_count = 5
          and category_median_amount = 12.00
          and category_mad = 1.00
          and flag_method = 'category_mad'
    ) != 1
