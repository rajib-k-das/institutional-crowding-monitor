"""
Load the extracted 13F tables into DuckDB as text; typing happens in dbt staging.

Input: data/raw/<data set>/*.tsv from ingest/download_13f.py, or the hand-built fixtures in tests/fixtures.
Output: raw.submission, raw.coverpage, raw.summarypage, raw.infotable, each with a source_data_set column.

Each file's header is checked against the columns documented in the SEC's 13F readme before loading,
so a format change fails here with a clear message instead of producing wrong numbers later.
The files are not quoted; quoting is switched off so that issuer names containing " load intact.

Usage:
    python ingest/load_13f.py                            # data/raw
    python ingest/load_13f.py --raw-dir tests/fixtures   # hand-checkable test filings (used in CI)
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "data" / "warehouse.duckdb"

# Columns kept from each file (the SEC files have more; unused ones are not loaded).
COLUMNS = {
    "submission": ["ACCESSION_NUMBER", "FILING_DATE", "SUBMISSIONTYPE", "CIK", "PERIODOFREPORT"],
    "coverpage": ["ACCESSION_NUMBER", "REPORTCALENDARORQUARTER", "ISAMENDMENT", "AMENDMENTNO", "AMENDMENTTYPE",
                  "FILINGMANAGER_NAME", "FILINGMANAGER_STATEORCOUNTRY", "REPORTTYPE"],
    "summarypage": ["ACCESSION_NUMBER", "OTHERINCLUDEDMANAGERSCOUNT", "TABLEENTRYTOTAL", "TABLEVALUETOTAL",
                    "ISCONFIDENTIALOMITTED"],
    "infotable": ["ACCESSION_NUMBER", "INFOTABLE_SK", "NAMEOFISSUER", "TITLEOFCLASS", "CUSIP", "FIGI", "VALUE",
                  "SSHPRNAMT", "SSHPRNAMTTYPE", "PUTCALL", "INVESTMENTDISCRETION", "OTHERMANAGER"],
}


def header(path: Path) -> list[str]:
    with open(path, encoding="utf-8", errors="replace") as f:
        return [c.strip().upper() for c in f.readline().rstrip("\r\n").split("\t")]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--raw-dir", type=Path, default=ROOT / "data" / "raw")
    args = parser.parse_args()

    data_sets = sorted(p for p in args.raw_dir.iterdir() if p.is_dir())
    if not data_sets:
        sys.exit(f"No data sets in {args.raw_dir}. Run: python ingest/download_13f.py")

    for data_set in data_sets:
        for table, columns in COLUMNS.items():
            path = data_set / f"{table.upper()}.tsv"
            if not path.exists():
                sys.exit(f"Missing {path}")
            missing = [c for c in columns if c not in header(path)]
            if missing:
                sys.exit(f"{path}: missing columns {missing}")

    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with duckdb.connect(str(DB_PATH)) as con:
        con.execute("create schema if not exists raw")
        for table, columns in COLUMNS.items():
            selects = []
            for data_set in data_sets:
                path = (data_set / f"{table.upper()}.tsv").as_posix()
                cols = ", ".join(f'"{c}" as {c.lower()}' for c in columns)
                selects.append(
                    f"select {cols}, '{data_set.name}' as source_data_set "
                    f"from read_csv('{path}', delim='\\t', header=true, all_varchar=true, quote='', escape='', "
                    f"normalize_names=false)"
                )
            con.execute(f"create or replace table raw.{table} as " + "\nunion all\n".join(selects))
            rows = con.execute(f"select count(*) from raw.{table}").fetchone()[0]
            print(f"  raw.{table:<12} {rows:>12,} rows from {len(data_sets)} data sets")


if __name__ == "__main__":
    main()
