"""
Download the SEC Form 13F data sets and extract the four tables this project uses.

Source: https://www.sec.gov/data-research/sec-markets-data/form-13f-data-sets
Each zip holds every 13F filing submitted in a three-month window (older files: a calendar quarter),
as tab-separated files. A quarter's holdings are filed within 45 days of quarter end, and amendments
can arrive months later, so one report quarter is spread over several zips.

The SEC asks automated clients to identify themselves. Set a User-Agent with your name and email first:
    export SEC_USER_AGENT="Your Name your.email@example.com"

Output: data/raw/<data set>/{SUBMISSION,COVERPAGE,SUMMARYPAGE,INFOTABLE}.tsv

Usage:
    python ingest/download_13f.py              # all data sets below (about 1.5 GB of zips)
    python ingest/download_13f.py --latest 4   # only the 4 most recent, for a quick start
"""

from __future__ import annotations

import argparse
import os
import sys
import time
import zipfile
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = ROOT / "data" / "raw"
ZIP_DIR = ROOT / "data" / "zips"

BASE = "https://www.sec.gov/files/structureddata/data/form-13f-data-sets/"
# Oldest first. Report quarters 2023 Q3 to 2026 Q2, plus the amendments filed after them.
DATA_SETS = [
    BASE + "2023q4_form13f.zip",
    BASE + "01jan2024-29feb2024_form13f.zip",
    BASE + "01mar2024-31may2024_form13f.zip",
    BASE + "01jun2024-31aug2024_form13f.zip",
    BASE + "01sep2024-30nov2024_form13f.zip",
    BASE + "01dec2024-28feb2025_form13f.zip",
    BASE + "01mar2025-31may2025_form13f.zip",
    BASE + "01jun2025-31aug2025_form13f.zip",
    BASE + "01sep2025-30nov2025_form13f.zip",
    BASE + "01dec2025-28feb2026_form13f.zip",
    BASE + "01mar2026-31may2026_form13f.zip",
    # The newest file sits under a different folder on the SEC site.
    "https://www.sec.gov/files/datastandardsinnovation/data/form-13f-data-sets/01jun2026-31aug2026_form13f.zip",
]
TABLES = ["SUBMISSION.tsv", "COVERPAGE.tsv", "SUMMARYPAGE.tsv", "INFOTABLE.tsv"]


def data_set_name(url: str) -> str:
    return url.rsplit("/", 1)[1].removesuffix("_form13f.zip")


def download(url: str, user_agent: str) -> Path:
    ZIP_DIR.mkdir(parents=True, exist_ok=True)
    path = ZIP_DIR / url.rsplit("/", 1)[1]
    if path.exists() and zipfile.is_zipfile(path):
        print(f"  have     {path.name}")
        return path
    print(f"  download {path.name} ...", flush=True)
    with requests.get(url, headers={"User-Agent": user_agent}, stream=True, timeout=120) as response:
        response.raise_for_status()
        tmp = path.with_suffix(".part")
        with open(tmp, "wb") as f:
            for chunk in response.iter_content(chunk_size=1 << 20):
                f.write(chunk)
        tmp.rename(path)
    time.sleep(0.5)  # stay well under the SEC's rate limit
    return path


def extract(zip_path: Path, name: str) -> None:
    out = RAW_DIR / name
    out.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as z:
        members = {Path(m).name.upper(): m for m in z.namelist()}
        for table in TABLES:
            if table.upper() not in members:
                sys.exit(f"{zip_path.name}: {table} not found (contains {sorted(members)})")
            target = out / table
            if not target.exists():
                with z.open(members[table.upper()]) as src, open(target, "wb") as dst:
                    while chunk := src.read(1 << 20):
                        dst.write(chunk)
    print(f"  extract  {name}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--latest", type=int, help="only the N most recent data sets")
    args = parser.parse_args()

    user_agent = os.environ.get("SEC_USER_AGENT", "").strip()
    if "@" not in user_agent:
        sys.exit('Set SEC_USER_AGENT first, e.g.  export SEC_USER_AGENT="Your Name your.email@example.com"')

    urls = DATA_SETS[-args.latest:] if args.latest else DATA_SETS
    for url in urls:
        extract(download(url, user_agent), data_set_name(url))
    print(f"Done: {len(urls)} data sets in {RAW_DIR.relative_to(ROOT)}/")


if __name__ == "__main__":
    main()
