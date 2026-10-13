-- One row per filing: who filed, for which quarter, when, and whether it amends an earlier filing.
select
    trim(s.accession_number)                                   as accession_number,
    trim(s.cik)                                                as manager_cik,
    trim(c.filingmanager_name)                                 as manager_name,
    trim(c.filingmanager_stateorcountry)                       as manager_state_or_country,
    trim(s.submissiontype)                                     as submission_type,
    trim(c.reporttype)                                         as report_type,
    {{ parse_sec_date('s.periodofreport') }}                   as period_of_report,
    {{ parse_sec_date('s.filing_date') }}                      as filing_date,
    coalesce(upper(trim(c.isamendment)) = 'Y', false)          as is_amendment,
    {{ to_number('c.amendmentno', 'integer') }}                as amendment_number,
    upper(nullif(trim(c.amendmenttype), ''))                   as amendment_type,
    {{ to_number('p.tableentrytotal') }}                       as reported_entry_count,
    {{ to_number('p.tablevaluetotal') }}                       as reported_value_total,
    coalesce(upper(trim(p.isconfidentialomitted)) = 'Y', false) as has_confidential_omissions,
    s.source_data_set
from {{ source('raw', 'submission') }} as s
left join {{ source('raw', 'coverpage') }} as c using (accession_number)
left join {{ source('raw', 'summarypage') }} as p using (accession_number)
