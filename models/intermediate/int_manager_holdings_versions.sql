-- Each report version's full list of positions: the base filing's positions plus any NEW HOLDINGS amendments
-- filed after the base, up to and including this version. One row per version and security.
with versions as (
    select * from {{ ref('int_report_versions') }}
),

filing_sequence as (
    select
        accession_number,
        manager_cik,
        period_of_report,
        filing_role,
        row_number() over (partition by manager_cik, period_of_report
                           order by filing_date, accession_number) as filing_sequence
    from {{ ref('int_filings') }}
),

contributing as (
    -- which filings make up each version
    select v.version_accession, f.accession_number
    from versions as v
    inner join filing_sequence as f
        on  f.manager_cik = v.manager_cik
        and f.period_of_report = v.period_of_report
        and f.filing_sequence <= v.version_number
        and (
            f.accession_number = v.base_accession
            or (f.filing_role = 'NEW HOLDINGS' and f.filing_sequence > v.base_sequence)
        )
)

select
    v.version_accession,
    v.manager_cik,
    v.period_of_report,
    v.valid_from,
    v.valid_to,
    h.cusip,
    sum(h.shares)                                                   as shares,
    sum(h.value_usd)                                                as value_usd,
    max(case when h.is_value_suspect then 1 else 0 end) = 1         as is_value_suspect,
    max(case when h.is_reported_in_thousands then 1 else 0 end) = 1 as was_reported_in_thousands
from versions as v
inner join contributing as c using (version_accession)
inner join {{ ref('int_filing_holdings_clean') }} as h on h.accession_number = c.accession_number
group by v.version_accession, v.manager_cik, v.period_of_report, v.valid_from, v.valid_to, h.cusip
