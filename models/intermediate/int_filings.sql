-- Holdings reports (originals and amendments) for the studied quarters, with each filing's role and deadline.
-- Role decides how a filing changes the manager's report for the quarter (decision 004):
--   ORIGINAL / RESTATEMENT replace everything filed before; NEW HOLDINGS adds lines to it.
with filings as (
    select *
    from {{ ref('stg_sec__filings') }}
    where submission_type in ('13F-HR', '13F-HR/A')
      and period_of_report between cast('{{ var("first_report_quarter") }}' as date)
                               and cast('{{ var("last_report_quarter") }}' as date)
),

with_deadline as (
    select
        *,
        period_of_report + 45 as deadline_raw
    from filings
)

select
    accession_number,
    manager_cik,
    manager_name,
    period_of_report,
    filing_date,
    submission_type,
    case
        when submission_type = '13F-HR' then 'ORIGINAL'
        when amendment_type = 'NEW HOLDINGS' then 'NEW HOLDINGS'
        else 'RESTATEMENT'   -- includes the few amendments with no type: treated as replacing the report
    end as filing_role,
    amendment_type,
    -- 45 days after quarter end, moved to Monday when it falls on a weekend (US holidays are not modeled)
    case dayofweek(deadline_raw)
        when 6 then deadline_raw + 2
        when 0 then deadline_raw + 1
        else deadline_raw
    end as filing_deadline,
    reported_entry_count,
    reported_value_total,
    source_data_set
from with_deadline
