-- Stock splits between one quarter and the next, inferred from the filings (decision 009): when managers holding a
-- stock in both quarters typically hold k times as many shares, and the price fell to about 1/k, it is a k-for-1
-- split. split_factor is the multiplier from this quarter's share count to the next (1 = no split).
with pairs as (
    select
        c.cusip,
        c.quarter_index,
        median(n.shares / c.shares) as median_share_ratio,
        count(*)                    as managers_in_both
    from {{ ref('int_holdings_final') }} as c
    inner join {{ ref('int_holdings_final') }} as n
        on  n.manager_cik = c.manager_cik
        and n.cusip = c.cusip
        and n.quarter_index = c.quarter_index + 1
    group by c.cusip, c.quarter_index
    having count(*) >= {{ var('min_managers_for_split') }}
),

candidates as (
    select
        pr.*,
        p0.consensus_price as price_now,
        p1.consensus_price as price_next,
        case
            when pr.median_share_ratio >= 1.9 then round(pr.median_share_ratio, 0)
            when pr.median_share_ratio <= 0.55 then 1 / round(1 / pr.median_share_ratio, 0)
        end as candidate_factor
    from pairs as pr
    inner join {{ ref('int_quarters') }} as q0 on q0.quarter_index = pr.quarter_index
    inner join {{ ref('int_quarters') }} as q1 on q1.quarter_index = pr.quarter_index + 1
    left join {{ ref('int_consensus_prices') }} as p0 on p0.cusip = pr.cusip and p0.period_of_report = q0.period_of_report
    left join {{ ref('int_consensus_prices') }} as p1 on p1.cusip = pr.cusip and p1.period_of_report = q1.period_of_report
)

select
    cusip,
    quarter_index,
    median_share_ratio,
    managers_in_both,
    case
        when candidate_factor is not null
         and abs(median_share_ratio / candidate_factor - 1) <= 0.03            -- holdings moved by a clean multiple
         and price_now > 0 and price_next > 0
         and abs(ln(price_next * candidate_factor / price_now)) < abs(ln(price_next / price_now))  -- price agrees
        then candidate_factor
        else 1
    end as split_factor
from candidates
