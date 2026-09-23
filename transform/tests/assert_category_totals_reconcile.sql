with categories as (
    select month_start, sum(spending) as spending,
        sum(unmatched_refunds) as unmatched_refunds
    from {{ ref('fct_monthly_spending_by_category') }}
    group by month_start
)

select coalesce(monthly.month_start, categories.month_start) as month_start
from {{ ref('fct_monthly_cashflow') }} as monthly
full outer join categories using (month_start)
where coalesce(monthly.spending, 0) != coalesce(categories.spending, 0)
    or coalesce(monthly.unmatched_refunds, 0) != coalesce(categories.unmatched_refunds, 0)
