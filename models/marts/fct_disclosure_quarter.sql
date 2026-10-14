-- One row per quarter: how complete the public picture was at the filing deadline compared with the final picture,
-- and how much the values-in-thousands error would distort a naive total (decisions 005 and 008).
with managers as (
    select
        period_of_report,
        count(*)                                                              as managers_final,
        sum(case when is_known_at_deadline then 1 else 0 end)                 as managers_known_at_deadline,
        sum(case when not original_filed_by_deadline then 1 else 0 end)       as managers_filed_late,
        sum(case when was_restated then 1 else 0 end)                         as managers_restated,
        sum(case when had_holdings_added then 1 else 0 end)                   as managers_holdings_added,
        sum(case when changed_after_deadline then 1 else 0 end)               as managers_changed_after_deadline,
        sum(value_usd_final)                                                  as value_usd_final,
        sum(value_usd_at_deadline)                                            as value_usd_at_deadline
    from {{ ref('fct_manager_quarter') }}
    group by period_of_report
),

originals as (
    select
        f.period_of_report,
        count(distinct f.accession_number)                                                as original_filings,
        count(distinct case when u.is_reported_in_thousands then f.accession_number end) as original_filings_in_thousands,
        count(distinct case when u.has_swapped_columns then f.accession_number end)      as original_filings_swapped,
        sum(case when not h.is_value_suspect then h.value_usd end)                         as value_usd_corrected,
        sum(case when not h.is_value_suspect then h.reported_value end)                    as value_usd_as_reported
    from {{ ref('int_filings') }} as f
    inner join {{ ref('int_filing_value_units') }} as u using (accession_number)
    left join {{ ref('int_filing_holdings_clean') }} as h using (accession_number)
    where f.filing_role = 'ORIGINAL'
    group by f.period_of_report
)

select
    q.period_of_report,
    q.quarter_index,
    q.filing_deadline,
    m.managers_final,
    m.managers_known_at_deadline,
    m.managers_filed_late,
    m.managers_restated,
    m.managers_holdings_added,
    m.managers_changed_after_deadline,
    m.value_usd_final,
    m.value_usd_at_deadline,
    o.original_filings,
    o.original_filings_in_thousands,
    o.original_filings_swapped,
    o.value_usd_corrected,
    o.value_usd_as_reported,
    o.value_usd_corrected - o.value_usd_as_reported as value_usd_missed_by_naive_total
from {{ ref('int_quarters') }} as q
left join managers as m on m.period_of_report = q.period_of_report
left join originals as o on o.period_of_report = q.period_of_report
