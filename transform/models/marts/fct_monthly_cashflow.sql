with monthly_components as (
    select
        cast(date_trunc('month', reporting_date) as date) as month_start,
        sum(income_amount) as income,
        sum(
            case when flow_type = 'expense' then -amount else 0 end
        ) as gross_spending,
        sum(
            case when refund_status = 'matched_full' then amount else 0 end
        ) as refunds,
        sum(unmatched_refund_amount) as unmatched_refunds,
        sum(spending_amount) as spending,
        count(*) filter (
            where flow_type in ('income', 'expense') or refund_status = 'matched_full'
        ) as included_transaction_count
    from {{ ref('fct_transactions') }}
    group by month_start
),

metrics as (
    select
        month_start,
        income,
        gross_spending,
        refunds,
        unmatched_refunds,
        spending,
        income - spending as net_cashflow,
        included_transaction_count
    from monthly_components
)

select
    *,
    case
        when income = 0 then null
        else net_cashflow / income
    end as savings_rate
from metrics
