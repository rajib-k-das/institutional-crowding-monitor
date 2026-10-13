-- One row per manager (filer CIK) with its latest name and how it files.
select
    manager_cik,
    max(case when period_of_report = last_period then manager_name end)      as manager_name,
    count(*)                                                                 as quarters_filed,
    sum(case when reported_in_thousands then 1 else 0 end)                   as quarters_in_thousands,
    sum(case when not original_filed_by_deadline then 1 else 0 end)         as quarters_filed_late,
    sum(case when was_restated then 1 else 0 end)                            as quarters_restated,
    median(pct_value_changed_by_next_quarter)                                as median_pct_value_changed_by_next_quarter,
    median(value_usd_final)                                                  as median_value_usd
from (
    select *, max(period_of_report) over (partition by manager_cik) as last_period
    from {{ ref('fct_manager_quarter') }}
) as m
group by manager_cik
