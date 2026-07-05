with transfer_candidates as (
    select *
    from {{ ref('int_transactions_classified') }}
    where base_flow_type in ('transfer', 'card_payment')
      and amount != 0
),

candidate_pairs as (
    select
        outflow.transaction_id as outflow_transaction_id,
        inflow.transaction_id as inflow_transaction_id,
        abs(
            date_diff(
                'day',
                outflow.transaction_date,
                inflow.transaction_date
            )
        ) as date_distance_days,
        case
            when outflow.base_flow_type = 'card_payment'
                or inflow.base_flow_type = 'card_payment'
                or (
                    outflow.account_type = 'checking'
                    and inflow.account_type = 'credit'
                )
                then 'card_payment'
            else 'transfer'
        end as match_flow_type,
        row_number() over (
            partition by outflow.transaction_id
            order by
                abs(
                    date_diff(
                        'day',
                        outflow.transaction_date,
                        inflow.transaction_date
                    )
                ),
                inflow.transaction_date,
                inflow.transaction_id
        ) as outflow_rank,
        row_number() over (
            partition by inflow.transaction_id
            order by
                abs(
                    date_diff(
                        'day',
                        outflow.transaction_date,
                        inflow.transaction_date
                    )
                ),
                outflow.transaction_date,
                outflow.transaction_id
        ) as inflow_rank
    from transfer_candidates as outflow
    inner join transfer_candidates as inflow
        on outflow.account_id != inflow.account_id
        and outflow.amount < 0
        and inflow.amount > 0
        and abs(outflow.amount) = inflow.amount
        and abs(
            date_diff(
                'day',
                outflow.transaction_date,
                inflow.transaction_date
            )
        ) <= 3
),

mutual_best_matches as (
    select
        md5(
            least(outflow_transaction_id, inflow_transaction_id)
            || '|'
            || greatest(outflow_transaction_id, inflow_transaction_id)
        ) as transfer_match_id,
        *
    from candidate_pairs
    where outflow_rank = 1
      and inflow_rank = 1
)

select
    transfer_match_id,
    outflow_transaction_id as transaction_id,
    inflow_transaction_id as matched_transaction_id,
    date_distance_days,
    match_flow_type
from mutual_best_matches

union all

select
    transfer_match_id,
    inflow_transaction_id as transaction_id,
    outflow_transaction_id as matched_transaction_id,
    date_distance_days,
    match_flow_type
from mutual_best_matches
