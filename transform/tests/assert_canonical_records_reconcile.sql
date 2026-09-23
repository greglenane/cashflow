-- Compare identities and values as well as aggregate account totals, so equal
-- and opposite corruptions cannot cancel out and silently pass reconciliation.
select coalesce(source.transaction_id, canonical.transaction_id) as transaction_id
from {{ ref('stg_plaid_transactions') }} as source
full outer join {{ ref('fct_transactions') }} as canonical using (transaction_id)
where source.transaction_id is null or canonical.transaction_id is null
    or source.account_id is distinct from canonical.account_id
    or source.transaction_date is distinct from canonical.transaction_date
    or source.amount is distinct from canonical.amount
    or source.merchant_normalized is distinct from canonical.merchant_normalized
    or source.source_file is distinct from canonical.source_file
