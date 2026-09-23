select facts.transaction_id
from {{ ref('fct_transactions') }} as facts
join {{ ref('stg_plaid_transactions') }} as source using (transaction_id)
where source.category_detailed in (
    'TRANSFER_IN_CARD_PAYMENT', 'TRANSFER_OUT_CARD_PAYMENT',
    'LOAN_PAYMENTS_CREDIT_CARD_PAYMENT'
) and (
    facts.flow_type != 'card_payment'
    or facts.income_amount != 0
    or facts.spending_amount != 0
    or facts.unmatched_refund_amount != 0
)
