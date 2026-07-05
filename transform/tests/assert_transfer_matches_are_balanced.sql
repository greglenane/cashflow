select
    transfer_match_id,
    count(*) as matched_rows,
    sum(amount) as net_amount
from {{ ref('fct_transactions') }}
where transfer_match_id is not null
group by transfer_match_id
having count(*) != 2
    or sum(amount) != 0
