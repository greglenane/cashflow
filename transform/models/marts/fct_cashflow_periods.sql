with cutoff as (
    select data_cutoff_date
    from {{ ref('fct_data_status') }}
    where ready_for_reporting
),

boundaries as (
    select
        data_cutoff_date,
        cast(date_trunc('month', data_cutoff_date) as date)
            as current_month_start,
        cast(
            date_trunc('month', data_cutoff_date - interval '1 month')
            as date
        ) as prior_month_start,
        cast(
            date_trunc('month', data_cutoff_date - interval '1 year')
            as date
        ) as prior_year_start,
        day(data_cutoff_date) as comparable_day_count
    from cutoff
),

periods as (
    select
        'current_mtd' as period_name,
        data_cutoff_date,
        current_month_start as period_start,
        data_cutoff_date as period_end
    from boundaries

    union all

    select
        'prior_month_comparable',
        data_cutoff_date,
        prior_month_start,
        cast(
            least(
                last_day(prior_month_start),
                prior_month_start
                    + (comparable_day_count - 1) * interval '1 day'
            )
            as date
        )
    from boundaries

    union all

    select
        'prior_year_comparable',
        data_cutoff_date,
        prior_year_start,
        cast(
            least(
                last_day(prior_year_start),
                prior_year_start
                    + (comparable_day_count - 1) * interval '1 day'
            )
            as date
        )
    from boundaries
),

period_components as (
    select
        periods.period_name,
        periods.data_cutoff_date,
        periods.period_start,
        periods.period_end,
        date_diff('day', periods.period_start, periods.period_end) + 1
            as comparable_day_count,
        coalesce(sum(transactions.income_amount), 0) as income,
        coalesce(sum(transactions.spending_amount), 0) as spending,
        coalesce(sum(transactions.unmatched_refund_amount), 0) as unmatched_refunds
    from periods
    left join {{ ref('fct_transactions') }} as transactions
        on transactions.reporting_date
            between periods.period_start and periods.period_end
    group by
        periods.period_name,
        periods.data_cutoff_date,
        periods.period_start,
        periods.period_end
)

select
    *,
    income - spending as net_cashflow,
    case
        when income = 0 then null
        else (income - spending) / income
    end as savings_rate
from period_components
