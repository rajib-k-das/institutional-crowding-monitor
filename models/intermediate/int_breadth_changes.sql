-- Change in ownership breadth per security, using only what was public at each quarter's filing deadline
-- (decision 011). Among managers whose reports for both this quarter and the previous one were public by this
-- quarter's deadline: holders now minus holders before, divided by the number of such managers.
with known as (
    select k.*, q.quarter_index
    from {{ ref('int_known_versions') }} as k
    inner join {{ ref('int_quarters') }} as q using (period_of_report)
),

current_reports as (
    select quarter_index, manager_cik, version_accession
    from known where snapshot = 'own_deadline'
),

previous_reports as (
    -- last quarter's report as known at this quarter's deadline
    select quarter_index + 1 as quarter_index, manager_cik, version_accession
    from known where snapshot = 'next_deadline'
),

managers_in_both as (
    select c.quarter_index, c.manager_cik, c.version_accession as current_version, p.version_accession as previous_version
    from current_reports as c
    inner join previous_reports as p using (quarter_index, manager_cik)
),

manager_counts as (
    select quarter_index, count(*) as managers_in_both
    from managers_in_both group by quarter_index
),

holders_now as (
    select m.quarter_index, h.cusip, count(*) as holders
    from managers_in_both as m
    inner join {{ ref('int_manager_holdings_versions') }} as h on h.version_accession = m.current_version
    where h.shares > 0
    group by m.quarter_index, h.cusip
),

holders_before as (
    select m.quarter_index, h.cusip, count(*) as holders
    from managers_in_both as m
    inner join {{ ref('int_manager_holdings_versions') }} as h on h.version_accession = m.previous_version
    where h.shares > 0
    group by m.quarter_index, h.cusip
),

combined as (
    select
        coalesce(n.quarter_index, b.quarter_index) as quarter_index,
        coalesce(n.cusip, b.cusip)                 as cusip,
        coalesce(n.holders, 0)                     as holders_now,
        coalesce(b.holders, 0)                     as holders_before
    from holders_now as n
    full outer join holders_before as b on b.quarter_index = n.quarter_index and b.cusip = n.cusip
)

select
    c.quarter_index,
    c.cusip,
    c.holders_now,
    c.holders_before,
    m.managers_in_both,
    cast(c.holders_now - c.holders_before as double) / m.managers_in_both as breadth_change,
    -- Holder count halved or doubled in one quarter, by 50+ managers: almost always a corporate event (acquisition,
    -- merger, spin-off or new CUSIP), not managers changing their minds. Excluded from the crowding analysis.
    (c.holders_now * 2 <= c.holders_before or c.holders_now >= 2 * c.holders_before)
        and abs(c.holders_now - c.holders_before) >= 50 as is_likely_corporate_event
from combined as c
inner join manager_counts as m using (quarter_index)
