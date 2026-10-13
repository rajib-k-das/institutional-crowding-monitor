-- Detects filings that report values in thousands of dollars, the format the SEC replaced with whole dollars in
-- January 2023 (decision 005). For each filing, each position's implied price is compared with the consensus
-- price; when the filing's median ratio is about 1/1000, every value in it is multiplied by 1,000.
with ratios as (
    select
        h.accession_number,
        (h.reported_value / h.shares) / p.consensus_price as price_ratio
    from {{ ref('int_filing_holdings') }} as h
    inner join {{ ref('int_filings') }} as f using (accession_number)
    inner join {{ ref('int_consensus_prices') }} as p
        on p.period_of_report = f.period_of_report and p.cusip = h.cusip
    where h.shares > 0 and h.reported_value > 0
),

by_filing as (
    select accession_number, median(price_ratio) as median_price_ratio, count(*) as positions_compared
    from ratios
    group by accession_number
)

select
    f.accession_number,
    b.median_price_ratio,
    coalesce(b.positions_compared, 0)                                       as positions_compared,
    coalesce(b.median_price_ratio between 0.0005 and 0.002, false)          as is_reported_in_thousands,
    case when b.median_price_ratio between 0.0005 and 0.002 then 1000 else 1 end as value_multiplier
from {{ ref('int_filings') }} as f
left join by_filing as b using (accession_number)
