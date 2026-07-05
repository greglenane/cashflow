with expenses as (
    select
        transaction_id,
        merchant_normalized,
        category,
        transaction_date,
        -amount as amount_absolute,
        lag(transaction_date) over (
            partition by merchant_normalized, category
            order by transaction_date, transaction_id
        ) as previous_transaction_date
    from {{ ref('fct_transactions') }}
    where flow_type = 'expense'
),

merchant_summary as (
    select
        merchant_normalized,
        category,
        count(*) as occurrence_count,
        min(transaction_date) as first_charge,
        max(transaction_date) as last_charge,
        median(amount_absolute) as typical_amount,
        min(amount_absolute) as minimum_amount,
        max(amount_absolute) as maximum_amount
    from expenses
    group by merchant_normalized, category
),

amount_stats as (
    select
        expenses.merchant_normalized,
        expenses.category,
        avg(
            cast(
                abs(
                    expenses.amount_absolute
                    - merchant_summary.typical_amount
                )
                / nullif(merchant_summary.typical_amount, 0)
                <= 0.20
                as integer
            )
        ) as amount_consistency
    from expenses
    inner join merchant_summary
        using (merchant_normalized, category)
    group by expenses.merchant_normalized, expenses.category
),

intervals as (
    select
        merchant_normalized,
        category,
        date_diff(
            'day',
            previous_transaction_date,
            transaction_date
        ) as interval_days
    from expenses
    where previous_transaction_date is not null
),

interval_medians as (
    select
        merchant_normalized,
        category,
        median(interval_days) as median_interval_days
    from intervals
    group by merchant_normalized, category
),

interval_stats as (
    select
        intervals.merchant_normalized,
        intervals.category,
        interval_medians.median_interval_days,
        max(
            abs(
                intervals.interval_days
                - interval_medians.median_interval_days
            )
        ) as maximum_interval_deviation_days,
        avg(
            cast(
                abs(
                    intervals.interval_days
                    - interval_medians.median_interval_days
                ) <= case
                    when median_interval_days between 5 and 9 then 2
                    when median_interval_days between 25 and 35 then 5
                    when median_interval_days between 80 and 100 then 10
                    when median_interval_days between 350 and 380 then 30
                    else 0
                end
                as integer
            )
        ) as interval_consistency
    from intervals
    inner join interval_medians
        using (merchant_normalized, category)
    group by
        intervals.merchant_normalized,
        intervals.category,
        interval_medians.median_interval_days
),

candidates as (
    select
        merchant_summary.*,
        interval_stats.median_interval_days,
        interval_stats.maximum_interval_deviation_days,
        interval_stats.interval_consistency,
        amount_stats.amount_consistency,
        (maximum_amount - minimum_amount)
            / nullif(typical_amount, 0) as amount_variance_ratio,
        case
            when median_interval_days between 5 and 9 then 'weekly'
            when median_interval_days between 25 and 35 then 'monthly'
            when median_interval_days between 80 and 100 then 'quarterly'
            when median_interval_days between 350 and 380 then 'annual'
        end as cadence
    from merchant_summary
    inner join amount_stats
        using (merchant_normalized, category)
    inner join interval_stats
        using (merchant_normalized, category)
),

qualified as (
    select *,
        case cadence
            when 'weekly' then 2
            when 'monthly' then 5
            when 'quarterly' then 10
            when 'annual' then 30
        end as interval_tolerance_days
    from candidates
    where occurrence_count >= 3
      and cadence is not null
      and amount_consistency >= 0.75
      and interval_consistency >= 0.75
)

select
    md5(merchant_normalized || '|' || category) as recurring_id,
    merchant_normalized,
    category,
    cadence,
    occurrence_count,
    typical_amount,
    minimum_amount,
    maximum_amount,
    amount_variance_ratio,
    amount_consistency,
    median_interval_days,
    maximum_interval_deviation_days,
    interval_consistency,
    first_charge,
    last_charge,
    last_charge + cast(round(median_interval_days) as integer)
        as predicted_next_charge,
    case cadence
        when 'weekly' then typical_amount * 52.0 / 12.0
        when 'monthly' then typical_amount
        when 'quarterly' then typical_amount / 3.0
        when 'annual' then typical_amount / 12.0
    end as monthly_equivalent_cost,
    least(
        1.0,
        0.40
        + least((occurrence_count - 3) * 0.05, 0.15)
        + 0.225 * amount_consistency
        + 0.225 * interval_consistency
    ) as confidence,
    concat(
        occurrence_count,
        ' charges; median interval ',
        round(median_interval_days, 1),
        ' days; amount range ',
        round(minimum_amount, 2),
        ' to ',
        round(maximum_amount, 2)
        ,
        '; amount consistency ',
        round(amount_consistency * 100, 0),
        '%; interval consistency ',
        round(interval_consistency * 100, 0),
        '%'
    ) as detection_reason
from qualified
