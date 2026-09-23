with transactions as (
    select * from {{ ref('stg_plaid_transactions') }}
),

accounts as (
    select * from {{ ref('stg_plaid_accounts') }}
),

classified as (
    select
        transactions.*,
        accounts.account_name,
        accounts.account_type,
        case
            when transactions.category_detailed in (
                'TRANSFER_IN_CARD_PAYMENT',
                'TRANSFER_OUT_CARD_PAYMENT',
                'LOAN_PAYMENTS_CREDIT_CARD_PAYMENT'
            ) then 'card_payment'
            when transactions.category_primary in (
                'TRANSFER_IN',
                'TRANSFER_OUT'
            ) then 'transfer'
            when transactions.category_primary = 'INCOME'
                and transactions.amount > 0 then 'income'
            when transactions.amount > 0 then 'refund'
            when transactions.amount < 0 then 'expense'
            else 'excluded'
        end as base_flow_type,
        case transactions.category_primary
            when 'BANK_FEES' then 'Bank Fees'
            when 'ENTERTAINMENT' then 'Entertainment'
            when 'FOOD_AND_DRINK' then 'Food & Drink'
            when 'GENERAL_MERCHANDISE' then 'Shopping'
            when 'GENERAL_SERVICES' then 'Services'
            when 'GOVERNMENT_AND_NON_PROFIT' then 'Government & Nonprofit'
            when 'HOME_IMPROVEMENT' then 'Home Improvement'
            when 'INCOME' then 'Income'
            when 'LOAN_PAYMENTS' then 'Loan Payments'
            when 'MEDICAL' then 'Medical'
            when 'PERSONAL_CARE' then 'Personal Care'
            when 'RENT_AND_UTILITIES' then 'Housing & Utilities'
            when 'TRANSPORTATION' then 'Transportation'
            when 'TRAVEL' then 'Travel'
            when 'TRANSFER_IN' then 'Transfer'
            when 'TRANSFER_OUT' then 'Transfer'
            else 'Uncategorized'
        end as plaid_category
    from transactions
    inner join accounts using (account_id)
),

category_rule_matches as (
    select
        classified.transaction_id,
        rules.rule_id,
        rules.category,
        row_number() over (
            partition by classified.transaction_id
            order by rules.priority, rules.rule_id
        ) as rule_rank
    from classified
    inner join {{ ref('category_rules') }} as rules
        on cast(rules.enabled as boolean)
        and regexp_matches(
            lower(classified.merchant_normalized),
            cast(rules.merchant_pattern as varchar)
        )
    where classified.base_flow_type in ('expense', 'refund')
),

selected_rules as (
    select transaction_id, rule_id, category
    from category_rule_matches
    where rule_rank = 1
)

select
    classified.*,
    selected_rules.rule_id as category_rule_id,
    case
        when classified.base_flow_type = 'card_payment' then 'Card Payment'
        when classified.base_flow_type = 'transfer' then 'Transfer'
        when classified.base_flow_type = 'income' then 'Income'
        when classified.base_flow_type = 'excluded' then 'Excluded'
        else coalesce(selected_rules.category, classified.plaid_category)
    end as category
from classified
left join selected_rules using (transaction_id)
