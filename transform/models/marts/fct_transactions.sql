with transactions as (
    select * from {{ ref('int_transactions_classified') }}
),

transfer_matches as (
    select * from {{ ref('int_transfer_matches') }}
)

select
    transactions.transaction_id,
    transactions.account_id,
    transactions.account_name,
    transactions.account_type,
    transactions.transaction_date,
    transactions.description_raw,
    transactions.merchant_normalized,
    transactions.amount,
    case
        when transfer_matches.match_flow_type is not null
            then transfer_matches.match_flow_type
        else transactions.base_flow_type
    end as flow_type,
    case
        when transfer_matches.match_flow_type = 'card_payment'
            then 'Card Payment'
        when transfer_matches.match_flow_type = 'transfer'
            then 'Transfer'
        else transactions.category
    end as category,
    transactions.category_rule_id,
    transfer_matches.transfer_match_id,
    transfer_matches.matched_transaction_id,
    transfer_matches.date_distance_days as match_date_distance_days,
    'plaid' as source,
    transactions.source_file,
    transactions.imported_at,
    refunds.purchase_transaction_id as matched_purchase_id,
    case
        when transactions.base_flow_type != 'refund' then 'not_applicable'
        when refunds.purchase_transaction_id is not null then 'matched_full'
        else 'unmatched'
    end as refund_status,
    coalesce(refunds.purchase_date, transactions.transaction_date)
        as reporting_date,
    coalesce(refunds.purchase_category, transactions.category)
        as reporting_category,
    case
        when transactions.base_flow_type = 'income'
            and transfer_matches.transaction_id is null then transactions.amount
        else 0
    end as income_amount,
    case
        when transactions.base_flow_type = 'expense'
            and transfer_matches.transaction_id is null then -transactions.amount
        when refunds.purchase_transaction_id is not null then -transactions.amount
        else 0
    end as spending_amount,
    case
        when transactions.base_flow_type = 'refund'
            and refunds.purchase_transaction_id is null then transactions.amount
        else 0
    end as unmatched_refund_amount,
    refunded_purchases.refund_transaction_id as matched_refund_id
from transactions
left join transfer_matches using (transaction_id)
left join {{ ref('int_refund_matches') }} as refunds
    on transactions.transaction_id = refunds.refund_transaction_id
left join {{ ref('int_refund_matches') }} as refunded_purchases
    on transactions.transaction_id = refunded_purchases.purchase_transaction_id
