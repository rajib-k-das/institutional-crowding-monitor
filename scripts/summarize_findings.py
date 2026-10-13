"""
Print the project's findings from the marts: disclosure gaps, values in thousands, portfolio staleness,
crowding vs subsequent returns, and breadth streaks.

Run after `dbt build`:
    python scripts/summarize_findings.py > findings.txt
"""

from pathlib import Path

import duckdb

DB_PATH = Path(__file__).resolve().parents[1] / "data" / "warehouse.duckdb"

CHECKS = {
    "1. What was public at the filing deadline vs the final picture": """
        select period_of_report as quarter, filing_deadline,
               managers_final, managers_known_at_deadline,
               round(100.0 * (managers_final - managers_known_at_deadline) / managers_final, 1) as pct_managers_missing_at_deadline,
               managers_filed_late, managers_restated, managers_holdings_added, managers_changed_after_deadline,
               round(value_usd_final / 1e12, 1) as value_final_tn,
               round(value_usd_at_deadline / 1e12, 1) as value_known_at_deadline_tn
        from marts.fct_disclosure_quarter order by 1
    """,
    "2. Original filings reported in thousands, and what a naive total misses": """
        select period_of_report as quarter, original_filings, original_filings_in_thousands,
               round(100.0 * original_filings_in_thousands / original_filings, 1) as pct_in_thousands,
               round(value_usd_as_reported / 1e12, 1) as naive_total_tn,
               round(value_usd_corrected / 1e12, 1) as corrected_total_tn,
               round(100.0 * value_usd_missed_by_naive_total / value_usd_corrected, 1) as pct_of_value_missed
        from marts.fct_disclosure_quarter order by 1
    """,
    "3. Largest managers reporting in thousands in the latest quarter (values after the fix)": """
        select manager_name, round(value_usd_final / 1e9, 1) as value_bn, positions_final
        from marts.fct_manager_quarter
        where reported_in_thousands and quarter_index = (select max(quarter_index) from marts.fct_manager_quarter)
        order by value_usd_final desc nulls last limit 10
    """,
    "4. Evidence: the three largest positions of the three largest managers in thousands (latest quarter)": """
        with flagged as (
            select f.accession_number, f.manager_name
            from intermediate.int_filings as f
            inner join intermediate.int_filing_value_units as u using (accession_number)
            where u.is_reported_in_thousands and f.filing_role = 'ORIGINAL'
              and f.quarter_index = (select max(quarter_index) from intermediate.int_filings)
            order by f.reported_value_total desc limit 3
        )
        select fl.manager_name, s.issuer_name, h.shares, h.reported_value,
               round(h.reported_value / h.shares, 4) as implied_price, round(h.consensus_price, 2) as consensus_price
        from flagged as fl
        inner join intermediate.int_filing_holdings_clean as h using (accession_number)
        left join intermediate.int_securities as s using (cusip)
        qualify row_number() over (partition by fl.manager_name order by h.value_usd desc) <= 3
        order by 1, h.value_usd desc
    """,
    "5. Staleness: share of a manager's disclosed portfolio (by value) changed or exited by its next report": """
        select period_of_report as quarter,
               count(pct_value_changed_by_next_quarter) as managers,
               round(100 * quantile_cont(pct_value_changed_by_next_quarter, 0.25), 1) as p25_changed_pct,
               round(100 * median(pct_value_changed_by_next_quarter), 1) as median_changed_pct,
               round(100 * quantile_cont(pct_value_changed_by_next_quarter, 0.75), 1) as p75_changed_pct,
               round(100.0 * avg(case when pct_value_changed_by_next_quarter > 0.5 then 1 else 0 end), 1)
                   as pct_managers_over_half_changed,
               round(100 * median(pct_value_exited_by_next_quarter), 1) as median_exited_pct
        from marts.fct_manager_quarter
        where pct_value_changed_by_next_quarter is not null
        group by 1 order by 1
    """,
    "6. Staleness by manager size (all quarters pooled)": """
        select case when value_usd_final < 1e8 then 'a. under $100M'
                    when value_usd_final < 1e9 then 'b. $100M-$1B'
                    when value_usd_final < 1e10 then 'c. $1B-$10B'
                    when value_usd_final < 1e11 then 'd. $10B-$100B'
                    else 'e. over $100B' end as manager_size,
               count(*) as manager_quarters,
               round(100 * median(pct_value_changed_by_next_quarter), 1) as median_changed_pct,
               round(100.0 * avg(case when pct_value_changed_by_next_quarter > 0.5 then 1 else 0 end), 1)
                   as pct_over_half_changed
        from marts.fct_manager_quarter
        where pct_value_changed_by_next_quarter is not null
        group by 1 order by 1
    """,
    "7. Crowding deciles: average return per decile, averaged over quarters (1 = most abandoned, 10 = most crowded into)": """
        select crowding_decile,
               count(*) as quarters, round(avg(stocks), 0) as avg_stocks,
               round(avg(avg_breadth_change) * 100, 2) as avg_breadth_change_pct,
               round(100 * avg(avg_return_next_quarter), 2) as return_next_qtr_pct_starts_before_public,
               round(100 * avg(avg_return_following_quarter), 2) as return_following_qtr_pct_starts_after_public
        from marts.fct_crowding_deciles group by 1 order by 1
    """,
    "8. Crowded minus abandoned (decile 10 minus decile 1), quarter by quarter": """
        with spread as (
            select quarter_index, period_of_report,
                   max(case when crowding_decile = 10 then avg_return_next_quarter end)
                   - max(case when crowding_decile = 1 then avg_return_next_quarter end) as spread_next,
                   max(case when crowding_decile = 10 then avg_return_following_quarter end)
                   - max(case when crowding_decile = 1 then avg_return_following_quarter end) as spread_following
            from marts.fct_crowding_deciles group by 1, 2
        )
        select period_of_report as signal_quarter,
               round(100 * spread_next, 2) as spread_next_qtr_pct,
               round(100 * spread_following, 2) as spread_following_qtr_pct
        from spread order by 1
    """,
    "9. Crowded minus abandoned: average and t-statistic across quarters": """
        with spread as (
            select quarter_index,
                   max(case when crowding_decile = 10 then avg_return_next_quarter end)
                   - max(case when crowding_decile = 1 then avg_return_next_quarter end) as spread_next,
                   max(case when crowding_decile = 10 then avg_return_following_quarter end)
                   - max(case when crowding_decile = 1 then avg_return_following_quarter end) as spread_following
            from marts.fct_crowding_deciles group by 1
        )
        select 'starts before data public (naive)' as window, count(spread_next) as quarters,
               round(100 * avg(spread_next), 2) as avg_spread_pct,
               round(avg(spread_next) / (stddev_samp(spread_next) / sqrt(count(spread_next))), 2) as t_stat
        from spread
        union all
        select 'starts after data public (implementable)', count(spread_following),
               round(100 * avg(spread_following), 2),
               round(avg(spread_following) / (stddev_samp(spread_following) / sqrt(count(spread_following))), 2)
        from spread
    """,
    "10. Breadth streaks: after 3+ quarters of rising breadth, how often does breadth fall next?": """
        with base as (
            select avg(case when breadth_change < 0 then 1.0 else 0 end) as base_rate
            from marts.fct_security_quarter
            where is_common_equity and breadth_change is not null
              and holders_previous_quarter >= 10
        )
        select count(*) as streaks,
               count(reversed_after) as streaks_with_next_quarter,
               round(100 * avg(case when reversed_after then 1.0 else 0 end), 1) as pct_reversed_after,
               round(100 * (select base_rate from base), 1) as pct_falling_any_quarter,
               round(avg(quarters_rising), 1) as avg_streak_quarters
        from marts.fct_breadth_streaks
    """,
    "11. Most crowded into and most abandoned stocks in the latest quarter (holders as known at the deadline)": """
        with latest as (
            select * from marts.fct_security_quarter
            where quarter_index = (select max(quarter_index) from marts.fct_security_quarter where breadth_change is not null)
              and is_common_equity and holders_previous_quarter >= 10
        )
        (select 'crowded into' as direction, issuer_name, holders_previous_quarter, holders_at_deadline,
                round(100 * breadth_change, 2) as breadth_change_pct
         from latest order by breadth_change desc limit 10)
        union all
        (select 'abandoned', issuer_name, holders_previous_quarter, holders_at_deadline,
                round(100 * breadth_change, 2)
         from latest order by breadth_change asc limit 10)
    """,
    "12. Sanity check: most widely held stocks in the latest quarter (final picture)": """
        select issuer_name, holders_final, round(value_usd_final / 1e9, 0) as value_bn, round(consensus_price, 2) as price
        from marts.fct_security_quarter
        where quarter_index = (select max(quarter_index) from marts.fct_security_quarter)
        order by holders_final desc limit 10
    """,
}


def main() -> None:
    with duckdb.connect(str(DB_PATH), read_only=True) as con:
        con.execute("set memory_limit = '3GB'; set preserve_insertion_order = false")
        for title, sql in CHECKS.items():
            print(f"\n== {title} ==")
            con.sql(sql).show(max_rows=60, max_width=250)


if __name__ == "__main__":
    main()
