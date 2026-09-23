select
    cast(date_trunc('month', reporting_date) as date) as month_start,
    reporting_category as category,
    sum(spending_amount) as spending,
    sum(unmatched_refund_amount) as unmatched_refunds,
    count(*) filter (where flow_type = 'expense') as purchase_count,
    count(*) filter (where refund_status = 'matched_full') as refund_count
from {{ ref('fct_transactions') }}
where flow_type in ('expense', 'refund')
group by month_start, reporting_category
