select *
from {{ ref('fct_transactions') }}
where
    (flow_type in ('income', 'refund') and amount <= 0)
    or (flow_type = 'expense' and amount >= 0)
