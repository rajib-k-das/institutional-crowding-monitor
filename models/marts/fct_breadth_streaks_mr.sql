{{ config(enabled=(target.type == 'snowflake')) }}
-- Snowflake only: the same runs as fct_breadth_streaks, found with MATCH_RECOGNIZE (row pattern matching) instead of
-- gaps-and-islands. A run is three or more consecutive quarters of rising breadth; "consecutive" means the quarter
-- numbers follow on with no gap. tests/data_tests/assert_breadth_streaks_engines_agree.sql checks both versions
-- return the same runs (decision 016).
with series as (
    select
        cusip,
        issuer_name,
        quarter_index,
        period_of_report,
        breadth_change
    from {{ ref('fct_security_quarter') }}
    where is_common_equity
      and breadth_change is not null
      and not is_likely_corporate_event
      and holders_previous_quarter >= {{ var('min_holders_for_crowding') }}
),

runs as (
    select *
    from series
        match_recognize (
            partition by cusip
            order by quarter_index
            measures
                min(issuer_name)          as issuer_name,
                first(quarter_index)      as first_quarter_index,
                last(quarter_index)       as last_quarter_index,
                first(period_of_report)   as first_period,
                last(period_of_report)    as last_period,
                count(*)                  as quarters_rising,
                sum(breadth_change)       as total_breadth_change
            one row per match
            after match skip past last row
            pattern (rise_start rise_next{2,})
            define
                rise_start as breadth_change > 0,
                rise_next  as breadth_change > 0 and quarter_index = lag(quarter_index) + 1
        )
)

select
    r.cusip,
    r.issuer_name,
    r.first_quarter_index,
    r.last_quarter_index,
    r.first_period,
    r.last_period,
    r.quarters_rising,
    r.total_breadth_change,
    a.breadth_change        as breadth_change_after,
    a.breadth_change < 0    as reversed_after
from runs as r
left join series as a on a.cusip = r.cusip and a.quarter_index = r.last_quarter_index + 1
