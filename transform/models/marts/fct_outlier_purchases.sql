with expenses as (
    select
        transaction_id,
        account_id,
        account_name,
        transaction_date,
        merchant_normalized,
        category,
        -amount as amount_absolute
    from {{ ref('fct_transactions') }}
    where flow_type = 'expense'
),

category_baselines as (
    select
        *,
        count(*) over (partition by category)
            as category_transaction_count,
        median(amount_absolute) over (partition by category)
            as category_median_amount
    from expenses
),

deviations as (
    select
        *,
        abs(amount_absolute - category_median_amount)
            as absolute_deviation
    from category_baselines
),

robust_statistics as (
    select
        *,
        median(absolute_deviation) over (partition by category)
            as category_mad
    from deviations
),

scored as (
    select
        *,
        case
            when category_mad > 0 then
                0.6745
                * (amount_absolute - category_median_amount)
                / category_mad
        end as modified_z_score,
        amount_absolute / nullif(category_median_amount, 0)
            as median_multiple
    from robust_statistics
),

flagged as (
    select *,
        case
            when category_transaction_count >= 5
                and category_mad > 0
                and modified_z_score >= 5
                and amount_absolute >= 250
                and median_multiple >= 3
                then 'category_mad'
            when category_transaction_count >= 5
                and category_mad = 0
                and amount_absolute >= 250
                and median_multiple >= 3
                then 'zero_mad_fallback'
            when category_transaction_count < 5
                and amount_absolute >= 1000
                and median_multiple >= 3
                then 'limited_history_threshold'
        end as flag_method
    from scored
)

select
    transaction_id,
    account_id,
    account_name,
    transaction_date,
    merchant_normalized,
    category,
    amount_absolute,
    category_transaction_count,
    category_median_amount,
    category_mad,
    absolute_deviation,
    modified_z_score,
    median_multiple,
    flag_method,
    case flag_method
        when 'category_mad' then concat(
            'Amount is ',
            round(median_multiple, 2),
            'x the category median; modified z-score ',
            round(modified_z_score, 2),
            ' based on median absolute deviation'
        )
        when 'zero_mad_fallback' then concat(
            'Category baseline has zero MAD; amount is ',
            round(median_multiple, 2),
            'x the category median'
        )
        when 'limited_history_threshold' then concat(
            'Limited category history; amount exceeds $1,000 and is ',
            round(median_multiple, 2),
            'x the category median'
        )
    end as detection_reason
from flagged
where flag_method is not null
