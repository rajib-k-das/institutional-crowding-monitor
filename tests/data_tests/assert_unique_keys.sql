-- Composite keys that must be unique. Returns one row per duplicated key.
select 'int_filing_holdings' as model, accession_number || '|' || cusip as key_value, count(*) as rows_found
from {{ ref('int_filing_holdings') }} group by accession_number, cusip having count(*) > 1
union all
select 'int_consensus_prices', cast(period_of_report as varchar) || '|' || cusip, count(*)
from {{ ref('int_consensus_prices') }} group by period_of_report, cusip having count(*) > 1
union all
select 'int_manager_holdings_versions', version_accession || '|' || cusip, count(*)
from {{ ref('int_manager_holdings_versions') }} group by version_accession, cusip having count(*) > 1
union all
select 'int_known_versions', cast(period_of_report as varchar) || '|' || snapshot || '|' || manager_cik, count(*)
from {{ ref('int_known_versions') }} group by period_of_report, snapshot, manager_cik having count(*) > 1
union all
select 'int_holdings_final', manager_cik || '|' || cast(quarter_index as varchar) || '|' || cusip, count(*)
from {{ ref('int_holdings_final') }} group by manager_cik, quarter_index, cusip having count(*) > 1
union all
select 'fct_security_quarter', cusip || '|' || cast(quarter_index as varchar), count(*)
from {{ ref('fct_security_quarter') }} group by cusip, quarter_index having count(*) > 1
union all
select 'fct_manager_quarter', manager_cik || '|' || cast(quarter_index as varchar), count(*)
from {{ ref('fct_manager_quarter') }} group by manager_cik, quarter_index having count(*) > 1
union all
select 'fct_crowding_deciles', cast(quarter_index as varchar) || '|' || cast(crowding_decile as varchar), count(*)
from {{ ref('fct_crowding_deciles') }} group by quarter_index, crowding_decile having count(*) > 1
