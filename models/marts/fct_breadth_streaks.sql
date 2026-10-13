-- Runs of three or more consecutive quarters in which a stock gained holders, and what happened to breadth in the
-- quarter after the run ended. Portable gaps-and-islands SQL; the Snowflake build adds a MATCH_RECOGNIZE version
-- that must agree with it.
with series as (
    select
        cusip,
        issuer_name,
        quarter_index,
        period_of_report,
        breadth_change,
        case when breadth_change > 0 then 1 else 0 end as is_rising
    from {{ ref('fct_security_quarter') }}
    where is_common_equity
      and breadth_change is not null
      and holders_previous_quarter >= {{ var('min_holders_for_crowding') }}
),

islands as (
    select
        *,
        quarter_index - row_number() over (partition by cusip, is_rising order by quarter_index) as island
    from series
),

runs as (
    select
        cusip,
        min(issuer_name)        as issuer_name,
        min(quarter_index)      as first_quarter_index,
        max(quarter_index)      as last_quarter_index,
        min(period_of_report)   as first_period,
        max(period_of_report)   as last_period,
        count(*)                as quarters_rising,
        sum(breadth_change)     as total_breadth_change
    from islands
    where is_rising = 1
    group by cusip, island
    having count(*) >= 3
)

select
    r.*,
    a.breadth_change                    as breadth_change_after,
    a.breadth_change < 0                as reversed_after
from runs as r
left join series as a on a.cusip = r.cusip and a.quarter_index = r.last_quarter_index + 1
