{{ config(enabled=target.name == 'dev') }}

select * from {{ ref('fct_data_status') }}
where account_count != 3 or ready_account_count != 3
    or data_cutoff_date != date '2026-07-03'
    or not ready_for_reporting
    or unmatched_refund_count != 1
