# Running the project on Snowflake

The same dbt models, loaded and built on a Snowflake trial account, then checked against the DuckDB build.
Plan on about two hours for steps 1–7, and use the **personal** Chrome profile and personal email throughout.

| Step | Where | What |
|---|---|---|
| 1 | Browser | Sign up for the trial |
| 2 | Snowsight | First sign-in, MFA, account identifier |
| 3 | Codespace | Make a key pair for the service user |
| 4 | Snowsight | Run `snowflake/01_setup.sql` |
| 5 | Codespace | Install, set the account, test the connection |
| 6 | Codespace | Test filings: load and build on Snowflake (expect PASS=62) |
| 7 | Codespace | Real SEC data: load and build |
| 8 | Codespace | Compare DuckDB and Snowflake |
| 9 | Snowsight | Snowflake features, with screenshots |
| 10 | Snowsight | Usage evidence, a few hours later |

## 1. Sign up

1. Go to **signup.snowflake.com**.
2. Fill in your name, your **personal** email, company "Independent", role "Data Analyst", country Canada. Continue.
3. Choose **Enterprise** edition, **AWS**, region **Canada (Central)**. Tick the terms and click **Get started**.
4. Skip the questionnaire. Open the activation email ("Activate your Snowflake account") and click the link.
5. Choose a username (e.g. `RAJIBDAS`) and a strong password. Save both in your password manager.

The trial lasts 30 days and includes $400 of credit. This project uses a few dollars of it.

## 2. First sign-in

1. Snowflake asks you to set up **multi-factor authentication**. Use an authenticator app or a passkey.
2. Find the **account identifier**: click your initials (bottom left) → your account name → **View account details**.
   Copy **Account identifier**; it looks like `ABCDEFG-XY12345` (organisation, hyphen, account).

## 3. Key pair (Codespace terminal)

dbt and the loader sign in as a service user with a key, not a password, so MFA does not get in the way.

```bash
mkdir -p ~/.snowflake && cd ~/.snowflake
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8 -nocrypt
openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
chmod 600 rsa_key.p8
grep -v "PUBLIC KEY" rsa_key.pub | tr -d '\n'; echo
cd /workspaces/institutional-crowding-monitor
```

The last `grep` prints the public key as one long line. Copy it. The private key stays in `~/.snowflake`, outside the
repository; `.gitignore` blocks key files as a second safeguard.

## 4. Setup script (Snowsight)

1. In Snowsight: **+ Create → SQL Worksheet** (or Projects → Worksheets → **+**).
2. Paste the contents of `snowflake/01_setup.sql`.
3. Replace `PASTE_PUBLIC_KEY_HERE` with the key from step 3 (keep the quotes).
4. Click the ▾ next to the Run button → **Run All**.
5. The last result should show `DBT_USER` with `has_rsa_public_key = true`.

It creates: a resource monitor capped at 20 credits a month, an X-Small warehouse that pauses after 60 seconds, the
`CROWDING` and `CROWDING_TEST` databases, a transformer role, a read-only analyst role and the service user.

## 5. Connect (Codespace terminal)

```bash
source .venv/bin/activate
pip install -r requirements-snowflake.txt
echo 'export SNOWFLAKE_ACCOUNT=ABCDEFG-XY12345' >> ~/.bashrc     # your identifier from step 2
source ~/.bashrc && source .venv/bin/activate
dbt debug --target snowflake
```

Expect `All checks passed!`.

## 6. Test filings on Snowflake

```bash
python ingest/load_snowflake.py --raw-dir tests/fixtures --database CROWDING_TEST
SNOWFLAKE_DATABASE=CROWDING_TEST dbt build --target snowflake
```

Expect **PASS=62**: the 60 DuckDB checks plus the `MATCH_RECOGNIZE` model and the test that compares it with the
portable version. The hand-worked answers now hold on both warehouses.

## 7. Real SEC data

```bash
ls data/raw          # the 12 extracted data sets; if empty, run python ingest/download_13f.py first
python ingest/load_snowflake.py
dbt build --target snowflake
```

The load converts the files to Parquet (about 10 minutes), uploads them to a Snowflake stage and copies them into
`CROWDING.RAW`, checking row counts. The dbt build takes roughly 15–30 minutes on the X-Small warehouse.

## 8. Compare the two warehouses

```bash
python scripts/compare_engines.py
```

Writes `docs/snowflake/parity.md`: row counts and headline numbers from every mart, computed on both. Expect every
check to match.

## 9. Snowflake features (Snowsight)

Open a new worksheet, paste `snowflake/02_features.sql` and run it **one block at a time** (select the lines, then
Cmd+Enter). Screenshot each result into `docs/snowflake/img/`:

| Block | Shows | Screenshot name |
|---|---|---|
| A | Zero-copy clone of the whole warehouse | `clone.png` |
| B | Time Travel: rows before a delete, then restored | `time_travel.png` |
| C | UNDROP | `undrop.png` |
| D | Analyst role reads the marts, is refused raw data | `rbac.png` (both results) |
| E | MATCH_RECOGNIZE streaks | `match_recognize.png` |

Block D's second query is meant to fail with "insufficient privileges"; that error is the evidence.

## 10. Usage evidence (a few hours later)

Snowflake's usage views lag by up to 3 hours. Then run `snowflake/03_evidence.sql` and screenshot the credits, the
work by stage and the table sizes as `usage.png`. Push everything:

```bash
git add -A && git commit -m "Snowflake build: parity check and evidence" && git push
```
