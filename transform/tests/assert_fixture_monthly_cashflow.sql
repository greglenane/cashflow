{{ config(enabled=target.name == 'dev') }}

with expected as (
    select
        date '2026-06-01' as month_start,
        2500.00::decimal(18, 2) as income,
        0.00::decimal(18, 2) as spending,
        2500.00::decimal(18, 2) as net_cashflow,
        1.00::decimal(18, 4) as savings_rate,
        1::bigint as included_transaction_count
    union all
    select
        date '2026-07-01',
        0.00::decimal(18, 2),
        250.50::decimal(18, 2),
        -250.50::decimal(18, 2),
        null::decimal(18, 4),
        4::bigint
),

actual as (
    select
        month_start,
        income,
        spending,
        net_cashflow,
        savings_rate,
        included_transaction_count
    from {{ ref('fct_monthly_cashflow') }}
)

select expected.*
from expected
full outer join actual using (month_start)
where actual.month_start is null
   or expected.month_start is null
   or actual.income is distinct from expected.income
   or actual.spending is distinct from expected.spending
   or actual.net_cashflow is distinct from expected.net_cashflow
   or actual.savings_rate is distinct from expected.savings_rate
   or actual.included_transaction_count
        is distinct from expected.included_transaction_count
