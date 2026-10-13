-- One row per filing and security: equity positions only (shares, not principal amounts; options excluded).
-- A security split over several lines of one filing (by investment discretion or other manager) is summed.
-- Numbers only: issuer names are kept once per security in int_securities, which keeps this large
-- aggregation (~40M lines) within a small machine's memory.
select
    h.accession_number,
    h.cusip,
    sum(h.amount)            as shares,
    sum(h.reported_value)    as reported_value,
    count(*)                 as lines
from {{ ref('stg_sec__holding_lines') }} as h
where h.amount_type = 'SH'
  and h.put_call is null
  and h.accession_number in (select accession_number from {{ ref('int_filings') }})
group by h.accession_number, h.cusip
