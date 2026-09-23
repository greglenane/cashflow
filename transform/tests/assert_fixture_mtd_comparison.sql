{{ config(enabled=target.name == 'dev') }}

select *
from {{ ref('fct_mtd_comparison') }}
where data_cutoff_date != date '2026-07-03'
   or comparable_day_count != 3
   or current_spending != 290.50
   or current_unmatched_refunds != 20.00
   or prior_month_spending != 120.00
   or prior_year_spending != 200.00
   or spending_change_vs_prior_month != 170.50
   or round(spending_pct_change_vs_prior_month, 6) != 1.420833
   or spending_change_vs_prior_year != 90.50
   or round(spending_pct_change_vs_prior_year, 6) != 0.452500
