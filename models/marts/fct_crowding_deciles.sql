-- Each quarter, common stocks held by enough managers are ranked into ten groups by the change in ownership breadth
-- known at the filing deadline (1 = most abandoned, 10 = most crowded into). Equal-weighted average returns per
-- group, for the quarter that starts before the data are public and for the one that starts after (decision 011).
-- Returns outside -95% to +300% are treated as data errors and left out of the averages.
with universe as (
    select *
    from {{ ref('fct_security_quarter') }}
    where is_common_equity
      and breadth_change is not null
      and holders_previous_quarter >= {{ var('min_holders_for_crowding') }}
),

ranked as (
    select
        *,
        ntile(10) over (partition by quarter_index order by breadth_change, cusip) as crowding_decile,
        case when return_next_quarter between -0.95 and 3 then return_next_quarter end           as clean_return_next,
        case when return_following_quarter between -0.95 and 3 then return_following_quarter end as clean_return_following
    from universe
)

select
    period_of_report,
    quarter_index,
    crowding_decile,
    count(*)                         as stocks,
    avg(breadth_change)              as avg_breadth_change,
    min(breadth_change)              as min_breadth_change,
    max(breadth_change)              as max_breadth_change,
    count(clean_return_next)         as stocks_with_return_next,
    avg(clean_return_next)           as avg_return_next_quarter,
    count(clean_return_following)    as stocks_with_return_following,
    avg(clean_return_following)      as avg_return_following_quarter
from ranked
group by period_of_report, quarter_index, crowding_decile
