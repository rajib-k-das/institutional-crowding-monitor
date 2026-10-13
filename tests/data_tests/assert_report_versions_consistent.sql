-- Report versions must chain without gaps or overlaps, and each manager-quarter has exactly one current version.
with v as (select * from {{ ref('int_report_versions') }})
select 'valid_to before valid_from' as problem, version_accession
from v where valid_to < valid_from
union all
select 'not exactly one current version', min(version_accession)
from v group by manager_cik, period_of_report having count(*) filter (where valid_to is null) <> 1
union all
select 'version without a base report', version_accession
from v where base_accession is null and filing_role <> 'NEW HOLDINGS'
