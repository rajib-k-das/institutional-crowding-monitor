-- Detects two filing-wide errors in how values are reported (decision 005), by comparing each position's implied
-- price with the consensus price for that security and quarter:
--   THOUSANDS  values in thousands of dollars (the format replaced in January 2023): median price ratio ~1/1000.
--              Fix: multiply every value by 1,000.
--   SWAPPED    the value and share-count columns are swapped: value ÷ shares is ~1/price, while shares ÷ value
--              matches the consensus price. Fix: swap them back.
-- Swaps are tested first: a swapped filing's median ratio (~1/price²) can land in the thousands band by chance.
with ratios as (
    select
        h.accession_number,
        (h.reported_value / h.shares) / p.consensus_price as price_ratio,
        (h.shares / h.reported_value) / p.consensus_price as swapped_price_ratio
    from {{ ref('int_filing_holdings') }} as h
    inner join {{ ref('int_filings') }} as f using (accession_number)
    inner join {{ ref('int_consensus_prices') }} as p
        on p.period_of_report = f.period_of_report and p.cusip = h.cusip
    where h.shares > 0 and h.reported_value > 0
),

by_filing as (
    select
        accession_number,
        median(price_ratio)          as median_price_ratio,
        median(swapped_price_ratio)  as median_swapped_price_ratio,
        count(*)                     as positions_compared
    from ratios
    group by accession_number
),

classified as (
    select
        f.accession_number,
        b.median_price_ratio,
        b.median_swapped_price_ratio,
        coalesce(b.positions_compared, 0) as positions_compared,
        case
            when b.median_price_ratio between 0.5 and 2 then 'NONE'
            when b.median_swapped_price_ratio between 0.8 and 1.25 then 'SWAPPED'
            when b.median_price_ratio between 0.0005 and 0.002 then 'THOUSANDS'
            else 'NONE'
        end as value_issue
    from {{ ref('int_filings') }} as f
    left join by_filing as b using (accession_number)
)

select
    *,
    value_issue = 'THOUSANDS'                                  as is_reported_in_thousands,
    value_issue = 'SWAPPED'                                    as has_swapped_columns,
    case when value_issue = 'THOUSANDS' then 1000 else 1 end   as value_multiplier
from classified
