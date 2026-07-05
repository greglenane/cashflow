{{ config(enabled=target.name == 'dev') }}

select transaction_id, category, category_rule_id
from {{ ref('fct_transactions') }}
where transaction_id = 'txn_grocery'
  and (
      category != 'Groceries'
      or category_rule_id != 'synthetic_market_grocery'
  )
