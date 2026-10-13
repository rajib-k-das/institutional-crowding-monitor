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
