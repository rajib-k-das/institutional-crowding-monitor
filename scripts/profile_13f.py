"""
Profile the loaded 13F data before modeling it: volumes, amendments, units, duplicates and data quality.

Run after `dbt build` (it reads the staging views):
    python scripts/profile_13f.py
"""

from pathlib import Path

import duckdb

DB_PATH = Path(__file__).resolve().parents[1] / "data" / "warehouse.duckdb"

CHECKS = {
    "1. Filings by report quarter and type": """
        select period_of_report, submission_type, count(*) as filings, count(distinct manager_cik) as managers
        from staging.stg_sec__filings group by all order by 1, 2
    """,
    "2. Amendments: type and how long after quarter end they were filed (holdings reports only)": """
        select submission_type, amendment_type, count(*) as filings,
               median(filing_date - period_of_report) as median_days_after_quarter_end,
               max(filing_date - period_of_report) as max_days
        from staging.stg_sec__filings where submission_type like '13F-HR%' group by all order by 1, 2
    """,
    "3. Originals filed after the 45-day deadline": """
        select count(*) filter (where filing_date - period_of_report > 45) as late,
               count(*) as originals,
               round(100.0 * count(*) filter (where filing_date - period_of_report > 45) / count(*), 1) as pct_late
        from staging.stg_sec__filings where submission_type = '13F-HR'
    """,
    "4. Managers with more than one original 13F-HR for the same quarter": """
        select count(*) as manager_quarters, sum(n) as filings from (
            select manager_cik, period_of_report, count(*) as n
            from staging.stg_sec__filings where submission_type = '13F-HR' group by all having count(*) > 1)
    """,
    "5. Holding lines: shares vs principal, options, FIGI coverage": """
        select amount_type, put_call is not null as is_option, count(*) as lines,
               round(100.0 * count(figi) / count(*), 1) as pct_with_figi
        from staging.stg_sec__holding_lines group by all order by 1, 2
    """,
    "6. Same security on several lines of one filing": """
        select count(*) as filing_securities_with_multiple_lines, sum(n) as lines from (
            select accession_number, cusip, count(*) as n from staging.stg_sec__holding_lines
            where amount_type = 'SH' and put_call is null group by all having count(*) > 1)
    """,
    "7. Value units: each line's implied price vs the median for that security and quarter (shares, no options)": """
        with lines as (
            select f.period_of_report, h.cusip, h.accession_number,
                   h.reported_value / nullif(h.amount, 0) as implied_price
            from staging.stg_sec__holding_lines as h
            inner join staging.stg_sec__filings as f using (accession_number)
            where h.amount_type = 'SH' and h.put_call is null and h.amount > 0 and h.reported_value > 0
        ),
        medians as (
            select period_of_report, cusip, median(implied_price) as median_price, count(*) as n
            from lines group by all having count(*) >= 5
        )
        select case
                 when ratio < 0.0002 then 'a. < 1/5000'
                 when ratio < 0.002  then 'b. ~1/1000 (value in thousands?)'
                 when ratio < 0.5    then 'c. 1/1000 to 1/2'
                 when ratio <= 2     then 'd. within 2x of median'
                 when ratio <= 500   then 'e. 2x to 500x'
                 when ratio <= 5000  then 'f. ~1000x'
                 else                     'g. > 5000x'
               end as price_vs_median,
               count(*) as lines, count(distinct accession_number) as filings
        from (select l.*, l.implied_price / m.median_price as ratio from lines as l inner join medians as m using (period_of_report, cusip))
        group by 1 order by 1
    """,
    "8. Filings where most lines look like thousands (median line ratio below 1/200)": """
        with lines as (
            select f.period_of_report, f.manager_name, h.cusip, h.accession_number,
                   h.reported_value / nullif(h.amount, 0) as implied_price
            from staging.stg_sec__holding_lines as h
            inner join staging.stg_sec__filings as f using (accession_number)
            where h.amount_type = 'SH' and h.put_call is null and h.amount > 0 and h.reported_value > 0
        ),
        medians as (select period_of_report, cusip, median(implied_price) as median_price
                    from lines group by all having count(*) >= 5),
        by_filing as (
            select accession_number, any_value(manager_name) as manager_name, any_value(period_of_report) as period,
                   median(l.implied_price / m.median_price) as median_ratio, count(*) as lines
            from lines as l inner join medians as m using (period_of_report, cusip) group by 1
        )
        select period, count(*) filter (where median_ratio < 0.005) as filings_in_thousands, count(*) as filings,
               any_value(manager_name) filter (where median_ratio < 0.005) as example_manager
        from by_filing group by 1 order by 1
    """,
    "9. Summary page vs information table (originals): do the reported totals match the lines?": """
        with lines as (select accession_number, count(*) as n_lines, sum(reported_value) as value
                       from staging.stg_sec__holding_lines group by 1)
        select count(*) as filings,
               count(*) filter (where f.reported_entry_count = l.n_lines) as entry_count_matches,
               count(*) filter (where abs(f.reported_value_total - l.value) <= 0.01 * f.reported_value_total) as value_within_1pct,
               count(*) filter (where l.accession_number is null) as no_lines
        from staging.stg_sec__filings as f left join lines as l using (accession_number)
        where f.submission_type = '13F-HR'
    """,
    "10. Most widely held securities in the latest complete quarter (sanity check)": """
        with q as (select max(period_of_report) - interval 3 month as p from staging.stg_sec__filings)
        select h.cusip, any_value(h.issuer_name) as issuer, count(distinct f.manager_cik) as holders,
               round(sum(h.reported_value) / 1e9, 1) as reported_value_bn
        from staging.stg_sec__holding_lines as h
        inner join staging.stg_sec__filings as f using (accession_number)
        where f.submission_type = '13F-HR' and h.amount_type = 'SH' and h.put_call is null
          and f.period_of_report = (select cast(last_day(p) as date) from q)
        group by 1 order by holders desc limit 10
    """,
    "11. Unparsed values (should all be 0)": """
        select (select count(*) from staging.stg_sec__filings where filing_date is null or period_of_report is null) as bad_dates,
               (select count(*) from staging.stg_sec__holding_lines where reported_value is null or amount is null) as bad_numbers
    """,
}


def main() -> None:
    with duckdb.connect(str(DB_PATH), read_only=True) as con:
        for title, sql in CHECKS.items():
            print(f"\n== {title} ==")
            con.sql(sql).show(max_rows=80, max_width=250)


if __name__ == "__main__":
    main()
