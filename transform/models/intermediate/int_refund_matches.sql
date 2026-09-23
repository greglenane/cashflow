-- Only unambiguous full refunds are allocated back to the purchase period.
with candidates as (
    select
        refund.transaction_id as refund_transaction_id,
        purchase.transaction_id as purchase_transaction_id,
        purchase.transaction_date as purchase_date,
        purchase.category as purchase_category,
        count(*) over (partition by refund.transaction_id) as refund_candidates,
        count(*) over (partition by purchase.transaction_id) as purchase_candidates
    from {{ ref('int_transactions_classified') }} as refund
    inner join {{ ref('int_transactions_classified') }} as purchase
        on refund.account_id = purchase.account_id
        and lower(trim(refund.merchant_normalized))
            = lower(trim(purchase.merchant_normalized))
        and nullif(trim(refund.merchant_normalized), '') is not null
        and refund.amount = -purchase.amount
        and date_diff('day', purchase.transaction_date, refund.transaction_date)
            between 0 and {{ var('refund_match_days', 180) }}
    where refund.base_flow_type = 'refund'
        and purchase.base_flow_type = 'expense'
        and refund.amount > 0
)

select
    refund_transaction_id,
    purchase_transaction_id,
    purchase_date,
    purchase_category
from candidates
where refund_candidates = 1 and purchase_candidates = 1
