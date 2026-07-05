with periods as (
    select *
    from {{ ref('fct_cashflow_periods') }}
)

select *
from periods
where comparable_day_count != (
    select comparable_day_count
    from periods
    where period_name = 'current_mtd'
)
   or period_end < period_start
