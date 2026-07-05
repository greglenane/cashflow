{{ config(enabled=target.name == 'dev') }}

with expected as (
    select 'txn_payroll' as transaction_id, 2500.00::decimal(18, 2) as amount, 'income' as flow_type
    union all
    select 'txn_grocery', -125.50::decimal(18, 2), 'expense'
    union all
    select 'txn_checking_payment', -500.00::decimal(18, 2), 'card_payment'
    union all
    select 'txn_credit_payment', 500.00::decimal(18, 2), 'card_payment'
    union all
    select 'txn_refund', 20.00::decimal(18, 2), 'refund'
),

actual as (
    select transaction_id, amount, flow_type
    from {{ ref('fct_transactions') }}
    where transaction_id in (select transaction_id from expected)
),

mismatches as (
    select expected.*
    from expected
    left join actual using (transaction_id, amount, flow_type)
    where actual.transaction_id is null
)

select * from mismatches
