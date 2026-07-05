with transaction_totals as (
    select
        cast(date_trunc('month', transaction_date) as date) as month_start,
        sum(case when flow_type = 'income' then amount else 0 end) as income,
        sum(
            case
                when flow_type = 'expense' then -amount
                when flow_type = 'refund' then -amount
                else 0
            end
        ) as spending
    from {{ ref('fct_transactions') }}
    group by month_start
)

select
    transaction_totals.month_start,
    transaction_totals.income as transaction_income,
    monthly.income as monthly_income,
    transaction_totals.spending as transaction_spending,
    monthly.spending as monthly_spending
from transaction_totals
inner join {{ ref('fct_monthly_cashflow') }} as monthly
    using (month_start)
where transaction_totals.income != monthly.income
   or transaction_totals.spending != monthly.spending
