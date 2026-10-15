{{ config(enabled=(target.type == 'snowflake')) }}
-- Snowflake only: the MATCH_RECOGNIZE runs (fct_breadth_streaks_mr) must be exactly the gaps-and-islands runs
-- (fct_breadth_streaks). Any row found by one method and not the other fails the test.
with portable as (
    select cusip, first_quarter_index, last_quarter_index, quarters_rising,
           round(total_breadth_change, 9) as total_breadth_change, reversed_after
    from {{ ref('fct_breadth_streaks') }}
),

pattern_matched as (
    select cusip, first_quarter_index, last_quarter_index, quarters_rising,
           round(total_breadth_change, 9) as total_breadth_change, reversed_after
    from {{ ref('fct_breadth_streaks_mr') }}
)

select 'only in gaps-and-islands' as found_by, * from (select * from portable minus select * from pattern_matched)
union all
select 'only in MATCH_RECOGNIZE', * from (select * from pattern_matched minus select * from portable)
