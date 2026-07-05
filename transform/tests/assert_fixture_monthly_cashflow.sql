{{ config(enabled=target.name == 'dev') }}

with expected as (
    select
        date '2025-07-01' as month_start,
        0.00::decimal(18, 2) as income,
        200.00::decimal(18, 2) as spending,
        -200.00::decimal(18, 2) as net_cashflow,
        null::decimal(18, 4) as savings_rate,
        1::bigint as included_transaction_count
    union all
    select
        date '2026-04-01',
        0.00::decimal(18, 2),
        546.00::decimal(18, 2),
        -546.00::decimal(18, 2),
        null::decimal(18, 4),
        5::bigint
    union all
    select
        date '2026-05-01',
        0.00::decimal(18, 2),
        20.00::decimal(18, 2),
        -20.00::decimal(18, 2),
        null::decimal(18, 4),
        1::bigint
    union all
    select
        date '2026-06-01',
        2500.00::decimal(18, 2) as income,
        120.00::decimal(18, 2) as spending,
        2380.00::decimal(18, 2) as net_cashflow,
        0.952::decimal(18, 4) as savings_rate,
        3::bigint as included_transaction_count
    union all
    select
        date '2026-07-01',
        0.00::decimal(18, 2),
        270.50::decimal(18, 2),
        -270.50::decimal(18, 2),
        null::decimal(18, 4),
        5::bigint
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
