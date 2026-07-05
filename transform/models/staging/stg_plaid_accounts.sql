{% if target.name == 'prod' %}
    {% set account_relation = ref('int_plaid_current_accounts') %}
{% else %}
    {% set account_relation = ref('plaid_accounts') %}
{% endif %}

select
    cast(account_id as varchar) as account_id,
    cast(account_name as varchar) as account_name,
    cast(account_type as varchar) as account_type,
    cast(institution as varchar) as institution
from {{ account_relation }}
