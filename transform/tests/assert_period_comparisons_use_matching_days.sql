with periods as (
    select *
    from {{ ref('fct_cashflow_periods') }}
)

select *
from periods
where comparable_day_count != least(
    day(data_cutoff_date), day(last_day(period_start))
)
   or period_end != period_start + cast(comparable_day_count - 1 as integer)
   or period_end < period_start
