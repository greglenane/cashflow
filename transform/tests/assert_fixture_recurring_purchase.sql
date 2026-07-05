{{ config(enabled=target.name == 'dev') }}

with expected as (
    select 'Synthetic Stream' as merchant_normalized
)

select expected.merchant_normalized
from expected
left join {{ ref('fct_recurring_purchases') }} as actual
    using (merchant_normalized)
where actual.recurring_id is null
   or actual.category != 'Entertainment'
   or actual.cadence != 'monthly'
   or actual.occurrence_count != 3
   or actual.typical_amount != 20.00
   or actual.predicted_next_charge != date '2026-08-01'
   or actual.monthly_equivalent_cost != 20.00
