with monthly_components as (
    select
        cast(date_trunc('month', transaction_date) as date) as month_start,
        sum(
            case when flow_type = 'income' then amount else 0 end
        ) as income,
        sum(
            case when flow_type = 'expense' then -amount else 0 end
        ) as gross_spending,
        sum(
            case when flow_type = 'refund' then amount else 0 end
        ) as refunds,
        count(*) filter (
            where flow_type in ('income', 'expense', 'refund')
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
        gross_spending - refunds as spending,
        income - (gross_spending - refunds) as net_cashflow,
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
