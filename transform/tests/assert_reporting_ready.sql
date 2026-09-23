select * from {{ ref('fct_data_status') }}
where not ready_for_reporting or data_cutoff_date is null
