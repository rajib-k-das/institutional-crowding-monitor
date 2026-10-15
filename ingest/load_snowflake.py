"""
Load the 13F tables into Snowflake: the same columns and text typing as ingest/load_13f.py, moved as Parquet files
through an internal stage (PUT, then COPY INTO). dbt then builds the same models on Snowflake.

The TSV files are read straight from the raw directory (not from the local DuckDB warehouse), so the hand-built
fixtures can be loaded into a separate test database to run the full test suite on Snowflake.

Connection: the CROWDING_TRANSFORMER role, as the DBT_USER service user with a key pair (docs/snowflake_guide.md).
    SNOWFLAKE_ACCOUNT            account identifier, e.g. ABCDEFG-XY12345 (required)
    SNOWFLAKE_PRIVATE_KEY_PATH   default ~/.snowflake/rsa_key.p8

Usage:
    python ingest/load_snowflake.py                                              # data/raw    -> CROWDING.RAW
    python ingest/load_snowflake.py --raw-dir tests/fixtures --database CROWDING_TEST
    python ingest/load_snowflake.py --export-only                                # Parquet files only, no Snowflake
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
import time
from pathlib import Path

import duckdb

sys.path.insert(0, str(Path(__file__).resolve().parent))
from load_13f import COLUMNS, header  # noqa: E402  (same columns and header checks as the DuckDB load)

ROOT = Path(__file__).resolve().parents[1]
PARQUET_DIR = ROOT / "data" / "parquet"


def export_parquet(raw_dir: Path) -> dict[str, int]:
    """Write each table to data/parquet/<table>/*.parquet (all text columns) and return its row count."""
    data_sets = sorted(p for p in raw_dir.iterdir() if p.is_dir())
    if not data_sets:
        sys.exit(f"No data sets in {raw_dir}. Run: python ingest/download_13f.py")
    for data_set in data_sets:
        for table, columns in COLUMNS.items():
            path = data_set / f"{table.upper()}.tsv"
            if not path.exists():
                sys.exit(f"Missing {path}")
            missing = [c for c in columns if c not in header(path)]
            if missing:
                sys.exit(f"{path}: missing columns {missing}")

    rows = {}
    con = duckdb.connect()
    con.execute("set memory_limit = '3GB'; set preserve_insertion_order = false")
    for table, columns in COLUMNS.items():
        out = PARQUET_DIR / table
        shutil.rmtree(out, ignore_errors=True)
        out.parent.mkdir(parents=True, exist_ok=True)
        cols = ", ".join(f'"{c}" as {c.lower()}' for c in columns)
        selects = [
            f"select {cols}, '{d.name}' as source_data_set "
            f"from read_csv('{(d / f'{table.upper()}.tsv').as_posix()}', delim='\\t', header=true, all_varchar=true, "
            f"quote='', escape='', normalize_names=false)"
            for d in data_sets
        ]
        # Files of ~100 MB upload in parallel and let COPY INTO load them in parallel.
        con.execute(f"copy ({' union all '.join(selects)}) to '{out.as_posix()}' "
                    f"(format parquet, compression zstd, file_size_bytes '100MB')")
        rows[table] = con.execute(f"select count(*) from read_parquet('{out.as_posix()}/*.parquet')").fetchone()[0]
        files = len(list(out.glob("*.parquet")))
        print(f"  exported {table:<12} {rows[table]:>12,} rows in {files} Parquet file(s)")
    return rows


def connect(database: str):
    import snowflake.connector

    account = os.environ.get("SNOWFLAKE_ACCOUNT")
    if not account:
        sys.exit("Set SNOWFLAKE_ACCOUNT first (docs/snowflake_guide.md, step 4).")
    key = os.environ.get("SNOWFLAKE_PRIVATE_KEY_PATH", str(Path.home() / ".snowflake" / "rsa_key.p8"))
    if not Path(key).exists():
        sys.exit(f"No private key at {key} (docs/snowflake_guide.md, step 3).")
    return snowflake.connector.connect(
        account=account,
        user="DBT_USER",
        private_key_file=key,
        role="CROWDING_TRANSFORMER",
        warehouse="CROWDING_WH",
        database=database,
        session_parameters={"QUERY_TAG": "crowding:load"},
    )


def load(rows: dict[str, int], database: str) -> None:
    started = time.time()
    with connect(database) as con:
        cur = con.cursor()
        cur.execute("create schema if not exists raw")
        cur.execute("use schema raw")
        cur.execute("create stage if not exists load_stage file_format = (type = parquet)")
        for table, columns in COLUMNS.items():
            column_defs = ", ".join(f"{c.lower()} varchar" for c in columns + ["SOURCE_DATA_SET"])
            cur.execute(f"create or replace table raw.{table} ({column_defs})")
            files = (PARQUET_DIR / table).as_posix()
            cur.execute(f"remove @load_stage/{table}/")
            cur.execute(f"put 'file://{files}/*.parquet' @load_stage/{table}/ "
                        f"parallel = 8 auto_compress = false overwrite = true")
            cur.execute(f"copy into raw.{table} from @load_stage/{table}/ "
                        f"match_by_column_name = case_insensitive purge = true")
            loaded = cur.execute(f"select count(*) from raw.{table}").fetchone()[0]
            status = "ok" if loaded == rows[table] else f"MISMATCH (expected {rows[table]:,})"
            print(f"  loaded   {database}.RAW.{table.upper():<12} {loaded:>12,} rows  {status}")
            if loaded != rows[table]:
                sys.exit("Row counts differ between the files and Snowflake; nothing downstream should be built.")
    print(f"Done in {time.time() - started:,.0f} s.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--raw-dir", type=Path, default=ROOT / "data" / "raw")
    parser.add_argument("--database", default="CROWDING")
    parser.add_argument("--export-only", action="store_true", help="write the Parquet files and stop")
    args = parser.parse_args()

    rows = export_parquet(args.raw_dir)
    if not args.export_only:
        load(rows, args.database)


if __name__ == "__main__":
    main()
