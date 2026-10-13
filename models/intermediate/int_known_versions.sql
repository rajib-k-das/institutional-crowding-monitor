-- Which version of each manager's report was public at three moments (decision 004):
--   own_deadline   the quarter's own filing deadline: what an investor could know when the data were due
--   next_deadline  the following quarter's deadline: used as the "previous quarter" when comparing quarters
--   final          the latest version, after every amendment
with quarters as (
    select * from {{ ref('int_quarters') }}
),

moments as (
    select period_of_report, 'final' as snapshot, cast(null as date) as as_of_date from quarters
    union all
    select period_of_report, 'own_deadline', filing_deadline from quarters
    union all
    select q.period_of_report, 'next_deadline', nq.filing_deadline
    from quarters as q
    inner join quarters as nq on nq.quarter_index = q.quarter_index + 1
)

select
    m.period_of_report,
    m.snapshot,
    m.as_of_date,
    v.manager_cik,
    v.version_accession
from moments as m
inner join {{ ref('int_report_versions') }} as v
    on  v.period_of_report = m.period_of_report
    and (
        (m.snapshot = 'final' and v.valid_to is null)
        or (m.snapshot <> 'final' and v.valid_from <= m.as_of_date)
    )
qualify row_number() over (partition by m.period_of_report, m.snapshot, v.manager_cik
                           order by v.version_number desc) = 1
