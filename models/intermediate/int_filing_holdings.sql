-- One row per filing and security: equity positions only (shares, not principal amounts; options excluded).
-- A security split over several lines of one filing (by investment discretion or other manager) is summed.
select
    h.accession_number,
    h.cusip,
    min(h.issuer_name)       as issuer_name,
    min(h.title_of_class)    as title_of_class,
    sum(h.amount)            as shares,
    sum(h.reported_value)    as reported_value,
    count(*)                 as lines
from {{ ref('stg_sec__holding_lines') }} as h
inner join {{ ref('int_filings') }} as f using (accession_number)
where h.amount_type = 'SH'
  and h.put_call is null
group by h.accession_number, h.cusip
