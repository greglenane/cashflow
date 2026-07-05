with transactions as (
    select * from {{ ref('stg_plaid_transactions') }}
),

accounts as (
    select * from {{ ref('stg_plaid_accounts') }}
)

select
    transactions.transaction_id,
    transactions.account_id,
    accounts.account_name,
    accounts.account_type,
    transactions.transaction_date,
    transactions.description_raw,
    transactions.merchant_normalized,
    transactions.amount,
    case
        when transactions.category_detailed in (
            'TRANSFER_IN_CARD_PAYMENT',
            'TRANSFER_OUT_CARD_PAYMENT'
        ) then 'card_payment'
        when transactions.category_primary in ('TRANSFER_IN', 'TRANSFER_OUT') then 'transfer'
        when transactions.category_primary = 'INCOME' and transactions.amount > 0 then 'income'
        when transactions.amount > 0 then 'refund'
        when transactions.amount < 0 then 'expense'
        else 'excluded'
    end as flow_type,
    replace(lower(transactions.category_primary), '_', ' ') as category,
    'plaid' as source,
    transactions.source_file,
    transactions.imported_at
from transactions
inner join accounts using (account_id)
