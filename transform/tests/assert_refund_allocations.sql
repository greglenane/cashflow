select refund.transaction_id
from {{ ref('fct_transactions') }} as refund
left join {{ ref('fct_transactions') }} as purchase
    on refund.matched_purchase_id = purchase.transaction_id
where refund.refund_status = 'matched_full' and (
    purchase.transaction_id is null
    or purchase.flow_type != 'expense'
    or refund.amount != -purchase.amount
    or refund.account_id != purchase.account_id
    or refund.reporting_date != purchase.transaction_date
    or refund.reporting_category != purchase.category
    or refund.spending_amount != -refund.amount
)
