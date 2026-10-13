-- A quarter-end price per security, from the 13F filings themselves: the median of value ÷ shares across all
-- managers reporting it in their original filing (decision 006), so each manager counts once. The median is robust
-- to the minority of filers reporting in thousands.
select
    f.period_of_report,
    h.cusip,
    median(h.reported_value / h.shares)   as consensus_price,
    count(*)                               as filings_priced
from {{ ref('int_filing_holdings') }} as h
inner join {{ ref('int_filings') }} as f using (accession_number)
where f.filing_role = 'ORIGINAL'
  and h.shares > 0
  and h.reported_value > 0
group by f.period_of_report, h.cusip
having count(*) >= {{ var('min_filings_for_price') }}
