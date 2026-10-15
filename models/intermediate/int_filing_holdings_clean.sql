-- Filing positions with values in dollars and share counts in their own column (decision 005): values in thousands
-- are multiplied by 1,000, and swapped value and share columns are swapped back. Positions whose price still
-- disagrees with the consensus by more than 5x are flagged: kept for holder counts, left out of value totals.
with fixed as (
    select
        h.accession_number,
        h.cusip,
        f.period_of_report,
        case when u.has_swapped_columns then h.reported_value else h.shares end              as shares,
        h.reported_value                                                                     as reported_value, -- as filed
        case when u.has_swapped_columns then h.shares else h.reported_value * u.value_multiplier end as value_usd,
        u.is_reported_in_thousands,
        u.has_swapped_columns
    from {{ ref('int_filing_holdings') }} as h
    inner join {{ ref('int_filings') }} as f using (accession_number)
    inner join {{ ref('int_filing_value_units') }} as u using (accession_number)
)

select
    x.accession_number,
    x.cusip,
    x.shares,
    x.reported_value,
    x.value_usd,
    x.is_reported_in_thousands,
    x.has_swapped_columns,
    p.consensus_price,
    coalesce(
        x.shares <= 0
        or x.value_usd <= 0
        or (x.value_usd / nullif(x.shares, 0)) / p.consensus_price not between 0.2 and 5,
        false
    ) as is_value_suspect
from fixed as x
left join {{ ref('int_consensus_prices') }} as p
    on p.period_of_report = x.period_of_report and p.cusip = x.cusip
