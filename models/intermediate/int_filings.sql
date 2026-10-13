-- Holdings reports (originals and amendments) for the studied quarters, with each filing's role and deadline.
-- Role decides how a filing changes the manager's report for the quarter (decision 004):
--   ORIGINAL / RESTATEMENT replace everything filed before; NEW HOLDINGS adds lines to it.
select
    f.accession_number,
    f.manager_cik,
    f.manager_name,
    f.period_of_report,
    q.quarter_index,
    f.filing_date,
    f.submission_type,
    case
        when f.submission_type = '13F-HR' then 'ORIGINAL'
        when f.amendment_type = 'NEW HOLDINGS' then 'NEW HOLDINGS'
        else 'RESTATEMENT'   -- includes the few amendments with no type: treated as replacing the report
    end as filing_role,
    f.amendment_type,
    q.filing_deadline,
    f.reported_entry_count,
    f.reported_value_total,
    f.source_data_set
from {{ ref('stg_sec__filings') }} as f
inner join {{ ref('int_quarters') }} as q using (period_of_report)
where f.submission_type in ('13F-HR', '13F-HR/A')
