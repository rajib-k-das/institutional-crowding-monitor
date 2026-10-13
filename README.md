# Institutional Crowding Monitor

[![dbt build](https://github.com/rajib-k-das/institutional-crowding-monitor/actions/workflows/ci.yml/badge.svg)](https://github.com/rajib-k-das/institutional-crowding-monitor/actions/workflows/ci.yml)

Which stocks are institutional investors crowding into or abandoning, and does crowding predict what happens next?
Built on every SEC Form 13F filing from 2023 to 2026, on **Snowflake** and DuckDB with dbt, with a **Tableau Public** dashboard.

> Work in progress. Status below.

| Layer | Output | Status |
|---|---|---|
| Ingestion | SEC 13F data sets: download, header checks, load | ✅ Done |
| Staging | Typed filings and holding lines | ✅ Done |
| Intermediate | Amendments as report versions (SCD Type 2), values in thousands detected and fixed, prices from the filings | ✅ Done |
| Marts | Disclosure gaps, staleness, crowding deciles vs returns, breadth streaks | ✅ Done |
| Snowflake | Same models on Snowflake, plus Snowflake-specific features | 🔜 Next |
| BI | Tableau Public dashboard | 🔜 |

## How to run it

Requires Python 3.11+.

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

export SEC_USER_AGENT="Your Name your.email@example.com"   # the SEC asks automated clients to identify themselves
python ingest/download_13f.py      # about 1.5 GB of zips into data/
python ingest/load_13f.py
dbt build
python scripts/profile_13f.py      # volumes, amendments, value units, duplicates
python scripts/summarize_findings.py # disclosure gaps, values in thousands, staleness, crowding vs returns
```

Hand-built test filings instead: `python ingest/load_13f.py --raw-dir tests/fixtures && dbt build`.
