{{ config(enabled=target.name == 'dev') }}

select *
from {{ ref('fct_mtd_comparison') }}
where data_cutoff_date != date '2026-07-03'
   or comparable_day_count != 3
   or current_spending != 270.50
   or prior_month_spending != 120.00
   or prior_year_spending != 200.00
   or spending_change_vs_prior_month != 150.50
   or round(spending_pct_change_vs_prior_month, 6) != 1.254167
   or spending_change_vs_prior_year != 70.50
   or round(spending_pct_change_vs_prior_year, 6) != 0.352500
