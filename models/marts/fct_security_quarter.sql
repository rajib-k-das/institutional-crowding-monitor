-- One row per security and quarter: who held it (final picture and as known at the deadline), how ownership
-- breadth changed, its consensus price, and its split-adjusted price return over the next two quarters.
--   return_next_quarter       quarter end -> next quarter end. Starts BEFORE the 13F data are public.
--   return_following_quarter  next quarter end -> the one after. Starts AFTER the data are public (no lookahead).
with final_holders as (
    select
        quarter_index,
        cusip,
        count(*)                                                  as holders_final,
        sum(case when not is_value_suspect then value_usd end)    as value_usd_final
    from {{ ref('int_holdings_final') }}
    group by quarter_index, cusip
)

select
    q.period_of_report,
    f.quarter_index,
    f.cusip,
    s.issuer_name,
    s.title_of_class,
    coalesce(s.is_common_equity, false)          as is_common_equity,
    f.holders_final,
    f.value_usd_final,
    b.holders_now                                as holders_at_deadline,
    b.holders_before                             as holders_previous_quarter,
    b.managers_in_both,
    b.breadth_change,
    coalesce(b.is_likely_corporate_event, false) as is_likely_corporate_event,
    p.consensus_price,
    r0.split_factor                              as split_factor_to_next_quarter,
    r0.return_to_next_quarter                    as return_next_quarter,
    r1.return_to_next_quarter                    as return_following_quarter
from final_holders as f
inner join {{ ref('int_quarters') }} as q on q.quarter_index = f.quarter_index
left join {{ ref('int_securities') }} as s on s.cusip = f.cusip
left join {{ ref('int_breadth_changes') }} as b on b.quarter_index = f.quarter_index and b.cusip = f.cusip
left join {{ ref('int_consensus_prices') }} as p on p.period_of_report = q.period_of_report and p.cusip = f.cusip
left join {{ ref('int_security_returns') }} as r0 on r0.cusip = f.cusip and r0.quarter_index = f.quarter_index
left join {{ ref('int_security_returns') }} as r1 on r1.cusip = f.cusip and r1.quarter_index = f.quarter_index + 1
