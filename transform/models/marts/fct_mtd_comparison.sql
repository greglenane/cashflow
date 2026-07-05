with periods as (
    select * from {{ ref('fct_cashflow_periods') }}
),

pivoted as (
    select
        max(data_cutoff_date) as data_cutoff_date,
        max(comparable_day_count) filter (
            where period_name = 'current_mtd'
        ) as comparable_day_count,
        max(income) filter (
            where period_name = 'current_mtd'
        ) as current_income,
        max(spending) filter (
            where period_name = 'current_mtd'
        ) as current_spending,
        max(net_cashflow) filter (
            where period_name = 'current_mtd'
        ) as current_net_cashflow,
        max(income) filter (
            where period_name = 'prior_month_comparable'
        ) as prior_month_income,
        max(spending) filter (
            where period_name = 'prior_month_comparable'
        ) as prior_month_spending,
        max(net_cashflow) filter (
            where period_name = 'prior_month_comparable'
        ) as prior_month_net_cashflow,
        max(income) filter (
            where period_name = 'prior_year_comparable'
        ) as prior_year_income,
        max(spending) filter (
            where period_name = 'prior_year_comparable'
        ) as prior_year_spending,
        max(net_cashflow) filter (
            where period_name = 'prior_year_comparable'
        ) as prior_year_net_cashflow
    from periods
)

select
    *,
    current_spending - prior_month_spending
        as spending_change_vs_prior_month,
    (current_spending - prior_month_spending)
        / nullif(prior_month_spending, 0)
        as spending_pct_change_vs_prior_month,
    current_spending - prior_year_spending
        as spending_change_vs_prior_year,
    (current_spending - prior_year_spending)
        / nullif(prior_year_spending, 0)
        as spending_pct_change_vs_prior_year,
    current_income - prior_month_income
        as income_change_vs_prior_month,
    current_income - prior_year_income
        as income_change_vs_prior_year
from pivoted
