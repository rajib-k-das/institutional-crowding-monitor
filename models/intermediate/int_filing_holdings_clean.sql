-- Filing positions with values in dollars. Positions whose price still disagrees with the consensus by more
-- than 5x after the units fix are flagged: kept for holder counts, left out of value totals (decision 005).
select
    h.accession_number,
    h.cusip,
    h.issuer_name,
    h.title_of_class,
    h.shares,
    h.reported_value * u.value_multiplier                                   as value_usd,
    u.is_reported_in_thousands,
    p.consensus_price,
    coalesce(
        h.shares <= 0
        or h.reported_value <= 0
        or (h.reported_value * u.value_multiplier / h.shares) / p.consensus_price not between 0.2 and 5,
        false
    )                                                                       as is_value_suspect
from {{ ref('int_filing_holdings') }} as h
inner join {{ ref('int_filings') }} as f using (accession_number)
inner join {{ ref('int_filing_value_units') }} as u using (accession_number)
left join {{ ref('int_consensus_prices') }} as p
    on p.period_of_report = f.period_of_report and p.cusip = h.cusip
