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
    transactions.imported_at
from transactions
left join transfer_matches using (transaction_id)
