-- Quarter-to-quarter price return per security from the consensus quarter-end prices, adjusted for splits.
-- Price return only: dividends are not in 13F data (decision 006).
select
    p0.cusip,
    q0.quarter_index,
    p0.consensus_price                                        as price_now,
    p1.consensus_price                                        as price_next,
    coalesce(s.split_factor, 1)                               as split_factor,
    p1.consensus_price * coalesce(s.split_factor, 1) / p0.consensus_price - 1 as return_to_next_quarter
from {{ ref('int_consensus_prices') }} as p0
inner join {{ ref('int_quarters') }} as q0 on q0.period_of_report = p0.period_of_report
inner join {{ ref('int_quarters') }} as q1 on q1.quarter_index = q0.quarter_index + 1
inner join {{ ref('int_consensus_prices') }} as p1 on p1.cusip = p0.cusip and p1.period_of_report = q1.period_of_report
left join {{ ref('int_split_factors') }} as s on s.cusip = p0.cusip and s.quarter_index = q0.quarter_index
