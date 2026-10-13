-- Composite keys that must be unique. Returns one row per duplicated key.
select 'int_filing_holdings' as model, accession_number || '|' || cusip as key_value, count(*) as rows_found
from {{ ref('int_filing_holdings') }} group by accession_number, cusip having count(*) > 1
union all
select 'int_consensus_prices', cast(period_of_report as varchar) || '|' || cusip, count(*)
from {{ ref('int_consensus_prices') }} group by period_of_report, cusip having count(*) > 1
union all
select 'int_manager_holdings_versions', version_accession || '|' || cusip, count(*)
from {{ ref('int_manager_holdings_versions') }} group by version_accession, cusip having count(*) > 1
