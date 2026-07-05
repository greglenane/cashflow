select
    cast(date_trunc('month', transaction_date) as date) as month_start,
    category,
    sum(
        case
            when flow_type = 'expense' then -amount
            when flow_type = 'refund' then -amount
            else 0
        end
    ) as spending,
    count(*) filter (where flow_type = 'expense') as purchase_count,
    count(*) filter (where flow_type = 'refund') as refund_count
from {{ ref('fct_transactions') }}
where flow_type in ('expense', 'refund')
group by month_start, category
