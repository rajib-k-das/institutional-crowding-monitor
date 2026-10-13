-- Each manager's positions per quarter in the final version of its report. One row per manager, quarter, security.
select
    k.manager_cik,
    q.quarter_index,
    k.period_of_report,
    h.cusip,
    h.shares,
    h.value_usd,
    h.is_value_suspect
from {{ ref('int_known_versions') }} as k
inner join {{ ref('int_quarters') }} as q using (period_of_report)
inner join {{ ref('int_manager_holdings_versions') }} as h on h.version_accession = k.version_accession
where k.snapshot = 'final'
  and h.shares > 0
