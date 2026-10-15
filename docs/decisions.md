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

## 008 — Filing deadlines follow the business-day rule

**Found in the data:** the first version moved weekend deadlines to Monday but ignored holidays, and flagged
2,079 Q4 2025 filings as late. That quarter's 45th day was Saturday 14 February 2026, and Monday 16 February was
Presidents' Day, so the real deadline was Tuesday 17 February.
**Choice:** a seed of US federal holidays (`seeds/us_federal_holidays.csv`); the deadline is the first day on or
after day 45 that is neither a weekend nor a holiday. A test pins every studied quarter's deadline, worked out by hand.

## 009 — Stock splits inferred from the filings

**Choice:** a split from one quarter to the next is inferred when managers holding the stock in both quarters
typically hold a whole multiple k of their previous shares (within 3%), and multiplying the price change by k
brings it closer to zero. Returns and portfolio changes are adjusted by k.
**Why:** without it, a 10-for-1 split reads as a 90% loss and as every holder having bought ten times more shares.
**Limits:** fractional splits (3-for-2) and spin-offs are not detected.

## 010 — Common stock only, by name

**Choice:** the crowding analysis keeps securities whose name and class do not look like an ETF, fund, preferred
share, warrant, unit or note. 13F data has no security-type field, so this is a name-based heuristic.
**Why:** ETF ownership tracks fund flows, not conviction in a company, and would dominate the most-held lists.

## 011 — Crowding measured only with what was public at the deadline

**Choice:** ownership breadth change for quarter Q compares, among managers whose Q and Q−1 reports were both
public by Q's filing deadline, how many held the stock at Q vs Q−1, divided by the number of such managers. Late
filings and later amendments are excluded. Returns are measured two ways: from Q's end to the next quarter's end
(the window most 13F studies use, which starts about 45 days *before* the data were public) and from the next
quarter's end to the one after (which starts *after* the data were public).
**Why:** the gap between the two is the lookahead that a naive analysis would count as skill.

## 012 — Staleness: how much of a disclosed portfolio has changed by the next report

**Choice:** for each manager and quarter, the share of the reported portfolio's value whose position was exited,
or changed by more than 10% (split-adjusted), by the manager's next quarterly report.
**Why:** a 13F is published up to 45 days after the quarter it describes; this measures how much of what an
investor reads has already been traded away by the next disclosure.

## 013 — A third reporting error: swapped value and share columns

**Found in the data:** the first thousands detector flagged CalSTRS, whose "NVIDIA 7,007,449,934 shares worth
$35,021,490" had an implied price of half a cent. Dividing the other way, 7,007,449,934 ÷ 35,021,490 = $200.09,
exactly NVIDIA's quarter-end price: the filing put the dollar value in the shares column and the share count in the
value column. Its median price ratio happened to fall inside the thousands band, so it was being multiplied by 1,000.
**Choice:** each filing is first tested for swapped columns (shares ÷ value matches the consensus price), then for
thousands; swapped filings have the two columns swapped back. A test filer with swapped columns pins the behaviour.

## 014 — Corporate events are not crowding

**Found in the data:** the "most abandoned" list was led by Honeywell (2,714 holders to 134), Hologic (669 to 4) and
Sealed Air (403 to 1), and Carnival topped the "crowded into" list (26 to 947). These are acquisitions, spin-offs and
new CUSIPs, not managers changing their minds.
**Choice:** a stock whose holder count halves or doubles in one quarter, by at least 50 managers, is flagged as a
likely corporate event and left out of the crowding deciles and streaks. The flagged stocks are listed by the
findings script so the rule can be checked.

## 015 — Reported values and share counts are FLOAT on Snowflake

**Found while porting:** DuckDB divides whole numbers as doubles. Snowflake divides `NUMBER(38,0)` columns with a
fixed number of decimal places (6, rising to 12 when divisions are chained), which is enough to blur the tiny ratios
the reporting-error checks rely on (a swapped filing's value ÷ shares ÷ price is about 1/price²).
**Choice:** `to_measure()` (`macros/cross_database.sql`) types reported values and share counts as `FLOAT` on Snowflake
and `BIGINT` on DuckDB. Whole numbers below 2^53 (about 9 × 10^15) are exact in a double, and the largest sums here
(about $50 trillion) are well inside that. `scripts/compare_engines.py` checks the two warehouses give the same answers.

## 016 — Streaks twice: gaps-and-islands and MATCH_RECOGNIZE

**Choice:** `fct_breadth_streaks` finds runs of rising ownership with portable gaps-and-islands SQL (row number
subtracted from the quarter number). On Snowflake, `fct_breadth_streaks_mr` finds the same runs with
`MATCH_RECOGNIZE`, which states the rule directly as a pattern: a rising quarter followed by two or more rising
quarters, each numbered one after the last.
**Why:** row pattern matching is the clearer way to express sequences, but it is not available in DuckDB. A
Snowflake-only test (`assert_breadth_streaks_engines_agree`) fails if either method finds a run the other does not.
