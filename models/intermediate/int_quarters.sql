-- One row per report quarter studied, numbered in order, with its 13F filing deadline: 45 days after quarter end,
-- moved to the next business day when that falls on a weekend or a US federal holiday (decision 008).
with periods as (
    select distinct period_of_report
    from {{ ref('stg_sec__filings') }}
    where submission_type in ('13F-HR', '13F-HR/A')
      and period_of_report between cast('{{ var("first_report_quarter") }}' as date)
                               and cast('{{ var("last_report_quarter") }}' as date)
      and extract(month from period_of_report) in (3, 6, 9, 12)
      and extract(day from period_of_report + 1) = 1          -- quarter-end dates only
),

candidates as (
    select p.period_of_report, p.period_of_report + 45 + o.day_offset as candidate_date
    from periods as p
    cross join (values (0), (1), (2), (3), (4), (5)) as o (day_offset)
)

select
    c.period_of_report,
    row_number() over (order by c.period_of_report)   as quarter_index,
    min(c.candidate_date)                             as filing_deadline
from candidates as c
left join {{ ref('us_federal_holidays') }} as h on h.holiday_date = c.candidate_date
where not ({{ is_weekend('c.candidate_date') }})
  and h.holiday_date is null
group by c.period_of_report
