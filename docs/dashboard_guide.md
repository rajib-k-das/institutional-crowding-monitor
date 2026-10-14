# Building the Tableau Public dashboard

Everything is done in the browser (Tableau Public web authoring). Tableau occasionally renames buttons; if a label
differs slightly, look for the closest match.

## 0. Produce the data (in the codespace)

```bash
source .venv/bin/activate
python scripts/export_for_tableau.py
```

This writes five files to `exports/`. Right-click each one in the codespace Explorer and choose **Download**, into a
new, empty folder (e.g. `Documents/crowding-dashboard`).

| File | One row per | View |
|---|---|---|
| `disclosure_by_quarter.csv` | report quarter | 1. What was public at the deadline; 2. Reporting errors |
| `staleness_distribution.csv` | manager size × 10-point bucket | 3. How stale a 13F is |
| `crowding_deciles.csv` | decile × return window | 4. Crowding vs returns |
| `latest_crowded_abandoned.csv` | stock (top and bottom 15) | 5. Latest quarter |
| `crowding_spread_by_quarter.csv` | quarter × return window | optional detail view |

## 1. Start a workbook

1. **public.tableau.com** → sign in (personal account) → **Create → Web Authoring**.
2. Upload **disclosure_by_quarter.csv**, then add the others **one at a time** with
   **Data → New Data Source → Upload from computer**, waiting for each to load.

## 2. View 1 — "Missing at the Deadline" (disclosure_by_quarter)

1. Rename the sheet **Missing at the Deadline**.
2. Drag **Quarter** to **Columns** and **Managers Missing At Deadline** to **Rows**. Marks: **Bar**.
3. Drag **Managers Changed After Deadline** to **Rows** too (a second chart under the first).
4. Drag **Is Latest Incomplete** to **Color**: False = dark blue, True = light grey.
5. Title: *Managers not yet filed at the deadline (top) and reports changed afterwards (bottom)*.
6. Caption: *The latest quarter is incomplete: late filings after 31 Aug 2026 are not in the data yet.*

## 3. View 2 — "Reporting Errors" (disclosure_by_quarter)

1. New sheet **Reporting Errors**.
2. Create a calculated field **Pct In Thousands**: `SUM([Original Filings In Thousands]) / SUM([Original Filings])`,
   format Percentage, 1 decimal.
3. Drag **Quarter** to **Columns**, **Pct In Thousands** to **Rows**. Marks: **Line**. Turn on labels.
4. Drag **Missed By Naive Total Tn** to **Rows** (second chart). Marks for it: **Bar**. Format: Number, 1 decimal,
   suffix ` tn`, prefix `$`.
5. Title: *Filers still reporting in thousands (top) and the value a naive total misses, $ trillion (bottom)*.

## 4. View 3 — "How Stale Is a 13F?" (staleness_distribution)

1. New sheet **Staleness**.
2. Make **Changed Pct Bucket Start** a **Dimension**, then drag it to **Columns**.
3. Drag **Manager Quarters** to **Rows** (SUM). Marks: **Bar**.
4. Drag **Manager Size** to **Color**.
5. Click the **SUM(Manager Quarters)** pill → **Quick Table Calculation → Percent of Total**; then
   **Edit Table Calculation → Compute Using → Changed Pct Bucket Start** so each size adds to 100%.
6. Title: *Share of the disclosed portfolio changed or exited by the next report (0 = unchanged, 90 = 90–100%)*.

## 5. View 4 — "Crowding vs Returns" (crowding_deciles)

1. New sheet **Crowding vs Returns**.
2. Make **Crowding Decile** a **Dimension** and drag it to **Columns**.
3. Drag **Avg Return** to **Rows** (SUM); format Percentage, 1 decimal. Marks: **Bar**.
4. Drag **Return Window** to **Color** and also to **Columns** after Crowding Decile (side-by-side bars):
   "Starts before data public" = grey, "Starts after data public" = blue.
5. Drag **Avg Return** to **Label**.
6. Title: *Average next-quarter return by crowding decile (1 = most abandoned, 10 = most crowded into)*.
7. Caption: *Spread 10 − 1 after the data were public: +3.3% a quarter, t = 1.9 over 9 quarters. Suggestive, not
   robust.*

## 6. View 5 — "Latest Quarter" (latest_crowded_abandoned)

1. New sheet **Latest Quarter**.
2. Drag **Issuer Name** to **Rows**, **Breadth Change** to **Columns** (SUM); format Percentage, 1 decimal.
3. Sort Issuer Name by **Breadth Change** descending.
4. Drag **Direction** to **Color**: Crowded into = blue, Abandoned = orange.
5. Drag **Holders Previous Quarter** and **Holders At Deadline** to **Tooltip**.
6. Title: *Change in the share of managers holding each stock, latest quarter*.

## 7. The dashboard

1. **New Dashboard**, **Fixed size 1400 × 1300**.
2. Title text: **How Usable Is 13F "Smart Money" Data?**, subtitle: *Every SEC Form 13F filing, Q3 2023 – Q2 2026:
   what was public at the deadline, reporting errors, staleness, and whether crowding predicts returns.*
3. Row 1: **Missing at the Deadline** | **Reporting Errors**. Row 2: **Staleness** | **Crowding vs Returns**.
   Row 3: **Latest Quarter**, full width.
4. Footer: *Built with Python, dbt, DuckDB and Snowflake. Code and methodology:
   github.com/rajib-k-das/institutional-crowding-monitor. Source: SEC Form 13F data sets. Not investment advice.*
5. Turn on captions for the views that have them (click the view → ▾ → Caption).

## 8. Publish

**File → Save**, name **Institutional Crowding Monitor**, with the dashboard tab active. Send over the public link
and a screenshot for the README.
