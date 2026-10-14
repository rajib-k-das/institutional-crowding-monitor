-- One row per manager and quarter: how and when the report was filed, its value, whether it was in thousands,
-- and how much of the disclosed portfolio had changed by the next quarter's report (decision 012).
with versions as (
    select
        manager_cik,
        period_of_report,
        max(manager_name)                                                         as manager_name,
        count(*)                                                                  as filings,
        max(case when filing_role = 'RESTATEMENT' then 1 else 0 end) = 1          as was_restated,
        max(case when filing_role = 'NEW HOLDINGS' then 1 else 0 end) = 1         as had_holdings_added,
        min(case when filing_role = 'ORIGINAL' then valid_from end)               as original_filing_date,
        max(filing_deadline)                                                      as filing_deadline
    from {{ ref('int_report_versions') }}
    group by manager_cik, period_of_report
),

units as (
    select f.manager_cik, f.period_of_report,
           max(case when u.is_reported_in_thousands then 1 else 0 end) = 1 as reported_in_thousands,
           max(case when u.has_swapped_columns then 1 else 0 end) = 1 as had_swapped_columns
    from {{ ref('int_filings') }} as f
    inner join {{ ref('int_filing_value_units') }} as u using (accession_number)
    group by f.manager_cik, f.period_of_report
),

snapshot_values as (
    select
        k.manager_cik,
        k.period_of_report,
        k.snapshot,
        k.version_accession,
        count(*)                                                   as positions,
        sum(case when not h.is_value_suspect then h.value_usd end) as value_usd
    from {{ ref('int_known_versions') }} as k
    inner join {{ ref('int_manager_holdings_versions') }} as h on h.version_accession = k.version_accession
    where k.snapshot in ('final', 'own_deadline')
    group by k.manager_cik, k.period_of_report, k.snapshot, k.version_accession
),

holdings as (
    select * from {{ ref('int_holdings_final') }}
),

filed_next as (
    select distinct manager_cik, quarter_index from holdings
),

changes as (
    -- positions valued this quarter, compared with the same manager's next-quarter report (split-adjusted)
    select
        c.manager_cik,
        c.quarter_index,
        sum(c.value_usd) as value_compared,
        sum(case when n.cusip is null then c.value_usd else 0 end) as value_exited,
        sum(case when n.cusip is null
                   or abs(n.shares / (c.shares * coalesce(s.split_factor, 1)) - 1) > 0.10
                 then c.value_usd else 0 end)                       as value_changed
    from holdings as c
    inner join filed_next as fn on fn.manager_cik = c.manager_cik and fn.quarter_index = c.quarter_index + 1
    left join holdings as n
        on n.manager_cik = c.manager_cik and n.quarter_index = c.quarter_index + 1 and n.cusip = c.cusip
    left join {{ ref('int_split_factors') }} as s on s.cusip = c.cusip and s.quarter_index = c.quarter_index
    where not c.is_value_suspect and c.value_usd > 0
    group by c.manager_cik, c.quarter_index
)

select
    v.manager_cik,
    v.manager_name,
    v.period_of_report,
    q.quarter_index,
    v.filings,
    v.original_filing_date,
    v.filing_deadline,
    coalesce(v.original_filing_date <= v.filing_deadline, false)   as original_filed_by_deadline,
    v.was_restated,
    v.had_holdings_added,
    coalesce(u.reported_in_thousands, false)                       as reported_in_thousands,
    coalesce(u.had_swapped_columns, false)                         as had_swapped_columns,
    fin.positions                                                  as positions_final,
    fin.value_usd                                                  as value_usd_final,
    dl.value_usd                                                   as value_usd_at_deadline,
    dl.version_accession is not null                               as is_known_at_deadline,
    coalesce(dl.version_accession <> fin.version_accession, false) as changed_after_deadline,
    ch.value_changed / nullif(ch.value_compared, 0)                as pct_value_changed_by_next_quarter,
    ch.value_exited / nullif(ch.value_compared, 0)                 as pct_value_exited_by_next_quarter
from versions as v
inner join {{ ref('int_quarters') }} as q on q.period_of_report = v.period_of_report
left join units as u on u.manager_cik = v.manager_cik and u.period_of_report = v.period_of_report
left join snapshot_values as fin
    on fin.manager_cik = v.manager_cik and fin.period_of_report = v.period_of_report and fin.snapshot = 'final'
left join snapshot_values as dl
    on dl.manager_cik = v.manager_cik and dl.period_of_report = v.period_of_report and dl.snapshot = 'own_deadline'
left join changes as ch on ch.manager_cik = v.manager_cik and ch.quarter_index = q.quarter_index
