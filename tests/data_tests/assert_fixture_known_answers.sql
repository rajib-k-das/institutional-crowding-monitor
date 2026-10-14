-- Hand-worked answers for the test filings in tests/fixtures (see make_fixtures.py).
-- Only runs when the fixtures are loaded; on the real SEC data it returns nothing.
{% set alpha_q4 = "'0000001001-24-000001'" %}
{% set alpha_q1 = "'0000001001-24-000002'" %}
{% set beta_q4 = "'0000001002-24-000001'" %}
{% set beta_q1 = "'0000001002-24-000002'" %}
{% set beta_q1_restated = "'0000001002-24-000003'" %}
{% set gamma_q1_added = "'0000001003-24-000002'" %}
{% set acme = "'000000AA1'" %}
{% set bolt = "'000000BB2'" %}

with is_fixture as (
    select count(*) > 0 as yes from {{ ref('stg_sec__filings') }}
    where manager_cik = '1001' and manager_name = 'ALPHA CAPITAL LLC'
),

checks as (
    select 'consensus price ACME Q4 2023' as check_name, 100.0 as expected,
           (select consensus_price from {{ ref('int_consensus_prices') }}
            where cusip = {{ acme }} and period_of_report = date '2023-12-31') as actual
    union all
    select 'consensus price BOLT Q1 2024 (suspect $60,000 line outvoted)', 60.0,
           (select consensus_price from {{ ref('int_consensus_prices') }}
            where cusip = {{ bolt }} and period_of_report = date '2024-03-31')
    union all
    select 'Beta Q4 detected as reported in thousands', 1000,
           (select value_multiplier from {{ ref('int_filing_value_units') }} where accession_number = {{ beta_q4 }})
    union all
    select 'Beta Q4 ACME value corrected to dollars', 200000,
           (select value_usd from {{ ref('int_filing_holdings_clean') }}
            where accession_number = {{ beta_q4 }} and cusip = {{ acme }})
    union all
    select 'Alpha Q4 not in thousands', 1,
           (select value_multiplier from {{ ref('int_filing_value_units') }} where accession_number = {{ alpha_q4 }})
    union all
    select 'Alpha Q1 ACME lines summed: shares', 1500,
           (select shares from {{ ref('int_filing_holdings') }} where accession_number = {{ alpha_q1 }} and cusip = {{ acme }})
    union all
    select 'Alpha Q1 ACME lines summed: value', 165000,
           (select value_usd from {{ ref('int_filing_holdings_clean') }}
            where accession_number = {{ alpha_q1 }} and cusip = {{ acme }})
    union all
    select 'Alpha Q1 BOLT put option excluded', 0,
           (select count(*) from {{ ref('int_filing_holdings') }} where accession_number = {{ alpha_q1 }} and cusip = {{ bolt }})
    union all
    select 'Beta Q1 bond (principal amount) excluded', 0,
           (select count(*) from {{ ref('int_filing_holdings') }} where accession_number = {{ beta_q1 }} and cusip = '000000CC3')
    union all
    select 'Beta Q1 has two report versions', 2,
           (select count(*) from {{ ref('int_report_versions') }} where manager_cik = '1002' and period_of_report = date '2024-03-31')
    union all
    select 'Beta Q1 first version ends when the restatement is filed (days after 1 Jan 2024)', 171,
           (select valid_to - date '2024-01-01' from {{ ref('int_report_versions') }} where version_accession = {{ beta_q1 }})
    union all
    select 'Beta Q1 restated version: ACME shares', 2500,
           (select shares from {{ ref('int_manager_holdings_versions') }}
            where version_accession = {{ beta_q1_restated }} and cusip = {{ acme }})
    union all
    select 'Beta Q1 original version: ACME shares', 2000,
           (select shares from {{ ref('int_manager_holdings_versions') }}
            where version_accession = {{ beta_q1 }} and cusip = {{ acme }})
    union all
    select 'Gamma Q1 after new-holdings amendment: positions', 2,
           (select count(*) from {{ ref('int_manager_holdings_versions') }} where version_accession = {{ gamma_q1_added }})
    union all
    select 'Gamma Q1 after new-holdings amendment: shares', 700,
           (select sum(shares) from {{ ref('int_manager_holdings_versions') }} where version_accession = {{ gamma_q1_added }})
    union all
    select 'Peer Two Q1 BOLT flagged as suspect value', 1,
           (select case when is_value_suspect then 1 else 0 end from {{ ref('int_filing_holdings_clean') }}
            where accession_number = '0000001006-24-000002' and cusip = {{ bolt }})
    union all
    select 'Peer One Q1 filed after the deadline', 0,
           (select case when is_filed_by_deadline then 1 else 0 end from {{ ref('int_report_versions') }}
            where version_accession = '0000001005-24-000002')
    union all
    select 'Q1 2024 deadline is 15 May 2024 (days after 1 Jan 2024)', 135,
           (select min(filing_deadline) - date '2024-01-01' from {{ ref('int_filings') }}
            where period_of_report = date '2024-03-31')
    union all
    select 'SPLIT inferred as a 2-for-1 split', 2,
           (select split_factor from {{ ref('int_split_factors') }} where cusip = '000000DD4' and quarter_index = 1)
    union all
    select 'SPLIT split-adjusted return, Q4 to Q1, in basis points', 500,
           (select round(return_next_quarter * 10000) from {{ ref('fct_security_quarter') }}
            where cusip = '000000DD4' and quarter_index = 1)
    union all
    select 'ACME return, Q4 to Q1, in basis points', 1000,
           (select round(return_next_quarter * 10000) from {{ ref('fct_security_quarter') }}
            where cusip = {{ acme }} and quarter_index = 1)
    union all
    select 'Managers with Q4 and Q1 reports public by the Q1 deadline', 5,
           (select managers_in_both from {{ ref('int_breadth_changes') }} where cusip = {{ acme }} and quarter_index = 2)
    union all
    select 'BOLT breadth change at the Q1 deadline, in basis points (4 holders to 3, of 5 managers)', -2000,
           (select round(breadth_change * 10000) from {{ ref('int_breadth_changes') }} where cusip = {{ bolt }} and quarter_index = 2)
    union all
    select 'ACME breadth change at the Q1 deadline (Gamma''s July amendment not yet public)', 0,
           (select breadth_change from {{ ref('int_breadth_changes') }} where cusip = {{ acme }} and quarter_index = 2)
    union all
    select 'Alpha: share of Q4 value changed by Q1, in basis points (ACME bought, BOLT sold, SPLIT only split)', 8621,
           (select round(pct_value_changed_by_next_quarter * 10000) from {{ ref('fct_manager_quarter') }}
            where manager_cik = '1001' and quarter_index = 1)
    union all
    select 'Alpha: share of Q4 value exited by Q1, in basis points', 1724,
           (select round(pct_value_exited_by_next_quarter * 10000) from {{ ref('fct_manager_quarter') }}
            where manager_cik = '1001' and quarter_index = 1)
    union all
    select 'Peer Three: nothing changed (its SPLIT holding doubled only because of the split)', 0,
           (select pct_value_changed_by_next_quarter from {{ ref('fct_manager_quarter') }}
            where manager_cik = '1007' and quarter_index = 1)
    union all
    select 'Peer One Q1 not known at the deadline', 0,
           (select case when is_known_at_deadline then 1 else 0 end from {{ ref('fct_manager_quarter') }}
            where manager_cik = '1005' and quarter_index = 2)
    union all
    select 'Beta Q1 changed after the deadline (restated)', 1,
           (select case when changed_after_deadline then 1 else 0 end from {{ ref('fct_manager_quarter') }}
            where manager_cik = '1002' and quarter_index = 2)
    union all
    select 'Value a naive Q4 total misses (Beta in thousands: 199,800; Swap Capital swapped: 123,500)', 323300,
           (select value_usd_missed_by_naive_total from {{ ref('fct_disclosure_quarter') }} where quarter_index = 1)
    union all
    select 'Swap Capital Q4 detected as swapped columns', 1,
           (select case when has_swapped_columns then 1 else 0 end from {{ ref('int_filing_value_units') }}
            where accession_number = '0000001009-24-000001')
    union all
    select 'Swap Capital Q4 ACME shares after the fix', 1000,
           (select shares from {{ ref('int_filing_holdings_clean') }}
            where accession_number = '0000001009-24-000001' and cusip = {{ acme }})
    union all
    select 'Swap Capital Q4 ACME value after the fix', 100000,
           (select value_usd from {{ ref('int_filing_holdings_clean') }}
            where accession_number = '0000001009-24-000001' and cusip = {{ acme }})
    union all
    select 'Swap Capital Q4 not mistaken for thousands', 0,
           (select case when is_reported_in_thousands then 1 else 0 end from {{ ref('int_filing_value_units') }}
            where accession_number = '0000001009-24-000001')
    union all
    select 'Delta 13F-NT notice has no report', 0,
           (select count(*) from {{ ref('int_report_versions') }} where manager_cik = '1004')
)

select check_name, expected, actual
from checks
where (select yes from is_fixture)
  and (actual is null or actual <> expected)
