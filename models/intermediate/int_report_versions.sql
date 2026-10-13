-- Every version of each manager's report for a quarter, as SCD Type 2: a new version starts each time the manager
-- files an original or an amendment, and is valid until the next filing (valid_to is null for the current one).
-- base_accession is the original or restatement the version is built on (decision 004).
with filings as (
    select
        *,
        row_number() over (partition by manager_cik, period_of_report
                           order by filing_date, accession_number) as filing_sequence,
        lead(filing_date) over (partition by manager_cik, period_of_report
                                order by filing_date, accession_number) as next_filing_date
    from {{ ref('int_filings') }}
),

bases as (
    select manager_cik, period_of_report, filing_sequence, accession_number
    from filings
    where filing_role in ('ORIGINAL', 'RESTATEMENT')
)

select
    v.accession_number                                         as version_accession,
    v.manager_cik,
    v.manager_name,
    v.period_of_report,
    v.filing_sequence                                          as version_number,
    v.filing_role,
    v.filing_date                                              as valid_from,
    v.next_filing_date                                         as valid_to,
    v.filing_deadline,
    v.filing_date <= v.filing_deadline                         as is_filed_by_deadline,
    b.accession_number                                         as base_accession,
    coalesce(b.filing_sequence, 0)                             as base_sequence
from filings as v
left join bases as b
    on  b.manager_cik = v.manager_cik
    and b.period_of_report = v.period_of_report
    and b.filing_sequence <= v.filing_sequence
qualify row_number() over (partition by v.accession_number order by b.filing_sequence desc nulls last) = 1
