select recurring_id, confidence
from {{ ref('fct_recurring_purchases') }}
where confidence < 0
   or confidence > 1
