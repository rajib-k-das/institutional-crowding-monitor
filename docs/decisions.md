# Design decisions

Each entry records a choice, why it was made, and what was rejected.

## 001 — SEC 13F data sets, not scraped filings

**Choice:** the SEC's quarterly Form 13F data sets (tab-separated extracts of every filing's XML), downloaded by
`ingest/download_13f.py`, rather than parsing individual filings from EDGAR.
**Why:** one consistent, documented format for every manager and quarter, about 3 million holding lines a quarter.
**Note:** a report quarter's filings are spread over several data sets: originals arrive within 45 days of quarter end,
amendments months later. The data sets are therefore loaded together and filings are grouped by report quarter.

## 002 — Load as text, type in staging, check headers first

**Choice:** the loader checks each file's header against the SEC readme and loads every column as text; dbt staging
does the typing, and unparseable values become null and fail a test.
**Why:** a format change fails loudly at the door instead of silently producing wrong numbers.
**Note:** the files are not quoted, so quoting is switched off; otherwise an issuer name containing `"` breaks the load.

## 003 — One codebase, two warehouses

**Choice:** the dbt models run on DuckDB (development and CI, free and permanent) and on Snowflake. Where the SQL
differs, a dispatch macro (`macros/cross_database.sql`) picks the right version for the target.
**Why:** the repository keeps building and testing after the Snowflake trial ends, and each Snowflake-specific feature
is shown next to a portable equivalent that is tested to give the same answer.

## 004 — Amendments as report versions (SCD Type 2)

**Found in the data:** 4,144 amendments, of two kinds. A RESTATEMENT (2,808, median 108 days after quarter end)
replaces the whole report; a NEW HOLDINGS amendment (1,336, median 232 days) adds positions to it. 27 amendments
state no type, and 7 managers filed two originals for the same quarter.
**Choice:** each filing starts a new version of the manager's report for that quarter, valid until the next filing
(`int_report_versions`). A version holds its base (the latest original or restatement) plus every NEW HOLDINGS
amendment filed after that base. Amendments with no type and second originals are treated as replacing the report.
**Why:** the question "what was public on date X" needs every version, not just the latest. Taking only the latest
filing would let analysis see positions that were disclosed months after the fact.

## 005 — Values reported in thousands are detected and fixed

**Found in the data:** since January 2023, 13F values must be in whole dollars, but 6,768 filings still report
values in thousands: each position's implied price (value ÷ shares) sits at about 1/1000 of what other managers
report for the same stock in the same quarter.
**Choice:** compare each position's implied price with the consensus price; when a filing's median ratio is
between 1/2000 and 1/500, multiply all its values by 1,000. Positions still more than 5x away from the consensus
after that are flagged as suspect: they count as holders but are left out of value totals.
**Rejected:** dropping these filings (it would remove real managers from holder counts), or fixing position by
position (a filing either uses thousands or it does not; the median of its positions decides it robustly).

## 006 — Prices come from the filings themselves

**Choice:** a security's quarter-end price is the median implied price across managers' original filings, required
from at least 5 managers. No outside price data is used.
**Why:** 13F values are quarter-end market values, so the filings already contain the price; the median across
thousands of managers is robust to the few in thousands or with typos. It also keeps the project free of licensed data.
**Limits:** prices exist only at quarter ends; returns derived from them exclude dividends, and stock splits must be
detected (next layer).

## 007 — Built to run on a free 2-core machine

**Found while building:** the first version of `int_filing_holdings` was killed for lack of memory on a standard
codespace (8 GB) while aggregating ~40M holding lines with four models running at once.
**Choice:** dbt runs one model at a time with DuckDB capped at 3 GB (it spills to disk beyond that); the large
aggregation carries numbers only, and issuer names are kept once per security in `int_securities`.
**Verified:** a 40M-line synthetic load builds in under 5 minutes with peak memory of about 3.2 GB.
