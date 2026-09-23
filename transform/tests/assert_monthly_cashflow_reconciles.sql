with transaction_totals as (
    select
        cast(date_trunc('month', reporting_date) as date) as month_start,
        sum(income_amount) as income,
        sum(spending_amount) as spending
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
full outer join {{ ref('fct_monthly_cashflow') }} as monthly
    using (month_start)
where transaction_totals.income is distinct from monthly.income
   or transaction_totals.spending is distinct from monthly.spending
