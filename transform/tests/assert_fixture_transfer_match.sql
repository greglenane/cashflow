{{ config(enabled=target.name == 'dev') }}

with expected as (
    select
        'txn_checking_payment' as transaction_id,
        'txn_credit_payment' as matched_transaction_id
    union all
    select
        'txn_credit_payment',
        'txn_checking_payment'
),

actual as (
    select
        transaction_id,
        matched_transaction_id,
        transfer_match_id,
        flow_type,
        match_date_distance_days
    from {{ ref('fct_transactions') }}
    where transaction_id in (
        'txn_checking_payment',
        'txn_credit_payment'
    )
)

select expected.*
from expected
left join actual using (transaction_id, matched_transaction_id)
where actual.transaction_id is null
   or actual.transfer_match_id is null
   or actual.flow_type != 'card_payment'
   or actual.match_date_distance_days != 0
