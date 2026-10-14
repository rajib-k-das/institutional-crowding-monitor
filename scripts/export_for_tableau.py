"""
Export the small CSV files behind the Tableau Public dashboard (docs/dashboard_guide.md).

Each file is shaped for one view, so the dashboard needs no joins and few calculated fields.
The latest quarter is flagged: late filers after the last data set (31 Aug 2026) are not in the data yet.

Run after `dbt build`:
    python scripts/export_for_tableau.py
"""

from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "data" / "warehouse.duckdb"
EXPORT_DIR = ROOT / "exports"

QUARTER = "strftime(period_of_report, '%Y') || ' Q' || quarter(period_of_report)"

EXPORTS = {
    # View 1. Disclosure: what was public at the deadline vs the final picture, and the reporting errors.
    "disclosure_by_quarter.csv": f"""
        select {QUARTER} as quarter, period_of_report, filing_deadline,
               quarter_index = (select max(quarter_index) from marts.fct_disclosure_quarter) as is_latest_incomplete,
               managers_final, managers_known_at_deadline,
               managers_final - managers_known_at_deadline as managers_missing_at_deadline,
               managers_filed_late, managers_restated, managers_holdings_added, managers_changed_after_deadline,
               round(value_usd_final / 1e12, 2) as value_final_tn,
               round(value_usd_at_deadline / 1e12, 2) as value_known_at_deadline_tn,
               original_filings, original_filings_in_thousands, original_filings_swapped,
               round(value_usd_as_reported / 1e12, 2) as naive_total_tn,
               round(value_usd_corrected / 1e12, 2) as corrected_total_tn,
               round(value_usd_missed_by_naive_total / 1e12, 2) as missed_by_naive_total_tn
        from marts.fct_disclosure_quarter
        order by period_of_report
    """,
    # View 2. Staleness: managers by share of portfolio value changed by the next report, in 10-point buckets.
    "staleness_distribution.csv": """
        select
            case when value_usd_final < 1e8 then '1. Under $100M'
                 when value_usd_final < 1e9 then '2. $100M-$1B'
                 when value_usd_final < 1e10 then '3. $1B-$10B'
                 else '4. Over $10B' end as manager_size,
            least(floor(pct_value_changed_by_next_quarter * 10), 9) * 10 as changed_pct_bucket_start,
            count(*) as manager_quarters
        from marts.fct_manager_quarter
        where pct_value_changed_by_next_quarter is not null and value_usd_final is not null
        group by all
        order by 1, 2
    """,
    # View 3. Crowding deciles: average return per decile, before vs after the data were public.
    "crowding_deciles.csv": """
        select crowding_decile, 'Starts before data public' as return_window,
               avg(avg_return_next_quarter) as avg_return, count(avg_return_next_quarter) as quarters
        from marts.fct_crowding_deciles group by 1
        union all
        select crowding_decile, 'Starts after data public',
               avg(avg_return_following_quarter), count(avg_return_following_quarter)
        from marts.fct_crowding_deciles group by 1
        order by 2, 1
    """,
    # View 4. Crowded minus abandoned, quarter by quarter, both windows.
    "crowding_spread_by_quarter.csv": f"""
        select {QUARTER} as signal_quarter, period_of_report, return_window, spread
        from (
            select period_of_report,
                   max(case when crowding_decile = 10 then avg_return_next_quarter end)
                   - max(case when crowding_decile = 1 then avg_return_next_quarter end) as before_public,
                   max(case when crowding_decile = 10 then avg_return_following_quarter end)
                   - max(case when crowding_decile = 1 then avg_return_following_quarter end) as after_public
            from marts.fct_crowding_deciles group by 1
        )
        unpivot (spread for return_window in (before_public as 'Starts before data public',
                                              after_public as 'Starts after data public'))
        order by period_of_report, return_window
    """,
    # View 5. Latest quarter: the 15 stocks most crowded into and the 15 most abandoned.
    "latest_crowded_abandoned.csv": f"""
        with latest as (
            select * from marts.fct_security_quarter
            where quarter_index = (select max(quarter_index) from marts.fct_security_quarter
                                   where breadth_change is not null)
              and is_common_equity and not is_likely_corporate_event
              and holders_previous_quarter >= 10
        )
        select {QUARTER} as quarter, direction, issuer_name, holders_previous_quarter, holders_at_deadline,
               holders_at_deadline - holders_previous_quarter as holder_change, breadth_change
        from (
            (select 'Crowded into' as direction, * from latest order by breadth_change desc limit 15)
            union all
            (select 'Abandoned', * from latest order by breadth_change asc limit 15)
        )
        order by breadth_change desc
    """,
}


def main() -> None:
    EXPORT_DIR.mkdir(exist_ok=True)
    with duckdb.connect(str(DB_PATH), read_only=True) as con:
        con.execute("set memory_limit = '3GB'")
        for name, sql in EXPORTS.items():
            path = EXPORT_DIR / name
            con.sql(sql).write_csv(str(path))
            rows = con.sql(f"select count(*) from read_csv_auto('{path}')").fetchone()[0]
            print(f"  wrote exports/{name:<32} {rows:>5} rows")


if __name__ == "__main__":
    main()
