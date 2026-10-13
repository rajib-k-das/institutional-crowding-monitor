"""
Measure what the cleaning in the intermediate layer changed: values in thousands, suspect prices, amendments
and late filings. These numbers feed the README and decide the next layer.

Run after `dbt build`:
    python scripts/check_cleaning.py
"""

from pathlib import Path

import duckdb

DB_PATH = Path(__file__).resolve().parents[1] / "data" / "warehouse.duckdb"

CHECKS = {
    "1. Original filings reported in thousands, and the value a naive total would miss": """
        select f.period_of_report,
               count(*) as filings,
               count(*) filter (where u.is_reported_in_thousands) as in_thousands,
               round(100.0 * count(*) filter (where u.is_reported_in_thousands) / count(*), 1) as pct_in_thousands,
               round(sum(f.reported_value_total) filter (where u.is_reported_in_thousands) * 999 / 1e9, 0) as missed_value_bn,
               round(100.0 * sum(f.reported_value_total) filter (where u.is_reported_in_thousands) * 1000
                     / sum(case when u.is_reported_in_thousands then f.reported_value_total * 1000
                                else f.reported_value_total end), 1) as pct_of_corrected_total
        from intermediate.int_filings as f
        inner join intermediate.int_filing_value_units as u using (accession_number)
        where f.filing_role = 'ORIGINAL'
        group by 1 order by 1
    """,
    "2. Filings whose units could not be checked (no position with a consensus price)": """
        select count(*) filter (where positions_compared = 0) as unchecked, count(*) as filings
        from intermediate.int_filing_value_units
    """,
    "3. Positions still suspect after the units fix (kept for holder counts, left out of values)": """
        select count(*) as positions, count(*) filter (where is_value_suspect) as suspect,
               round(100.0 * count(*) filter (where is_value_suspect) / count(*), 2) as pct_suspect,
               round(100.0 * count(*) filter (where consensus_price is null) / count(*), 1) as pct_no_consensus_price
        from intermediate.int_filing_holdings_clean
    """,
    "4. Amendments and late filings per quarter": """
        select period_of_report,
               count(distinct manager_cik) as managers,
               count(distinct manager_cik) filter (where filing_role = 'RESTATEMENT') as restated,
               count(distinct manager_cik) filter (where filing_role = 'NEW HOLDINGS') as added_holdings,
               count(*) filter (where filing_role = 'ORIGINAL' and not is_filed_by_deadline) as late_originals
        from intermediate.int_report_versions group by 1 order by 1
    """,
    "5. What was public at the deadline vs the final picture (value of positions, $bn)": """
        with at_deadline as (
            select * from intermediate.int_report_versions
            where valid_from <= filing_deadline
            qualify row_number() over (partition by manager_cik, period_of_report order by version_number desc) = 1
        ),
        final as (
            select * from intermediate.int_report_versions where valid_to is null
        ),
        value_of as (
            select version_accession, sum(value_usd) filter (where not is_value_suspect) as value_usd, count(*) as positions
            from intermediate.int_manager_holdings_versions group by 1
        )
        select f.period_of_report,
               count(*) as managers_final,
               count(d.version_accession) as managers_known_at_deadline,
               round(sum(fv.value_usd) / 1e9, 0) as final_value_bn,
               round(sum(dv.value_usd) / 1e9, 0) as value_known_at_deadline_bn,
               count(*) filter (where d.version_accession <> f.version_accession) as managers_changed_after_deadline
        from final as f
        left join at_deadline as d using (manager_cik, period_of_report)
        left join value_of as fv on fv.version_accession = f.version_accession
        left join value_of as dv on dv.version_accession = d.version_accession
        group by 1 order by 1
    """,
    "6. Largest managers reporting in thousands in the latest quarter (corrected value)": """
        select f.manager_name, round(f.reported_value_total * 1000 / 1e9, 1) as corrected_value_bn,
               round(u.median_price_ratio, 5) as median_price_ratio, u.positions_compared
        from intermediate.int_filings as f
        inner join intermediate.int_filing_value_units as u using (accession_number)
        where u.is_reported_in_thousands and f.filing_role = 'ORIGINAL'
          and f.period_of_report = (select max(period_of_report) from intermediate.int_filings)
        order by f.reported_value_total desc limit 10
    """,
}


def main() -> None:
    with duckdb.connect(str(DB_PATH), read_only=True) as con:
        for title, sql in CHECKS.items():
            print(f"\n== {title} ==")
            con.sql(sql).show(max_rows=60, max_width=250)


if __name__ == "__main__":
    main()
