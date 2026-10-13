"""
Write a small, hand-checkable set of 13F filings in the SEC's data set layout (tab-separated, DD-MON-YYYY dates).

Three managers, three securities, two report quarters (Q4 2023 and Q1 2024), and every awkward case the
pipeline has to handle. Expected results are asserted in tests/data_tests/assert_fixture_known_answers.sql.

    Alpha Capital (CIK 1001)
      Q4 2023  original   ACME 1,000 sh $100,000 | BOLT 500 sh $25,000 | SPLIT 100 sh $20,000
      Q1 2024  original   ACME split over two rows (1,000 + 500 sh, $165,000 in total) | BOLT put option (excluded)
                          | SPLIT 200 sh $21,000 (the stock split 2-for-1: the same position, not a purchase)
    Beta Partners (CIK 1002)
      Q4 2023  original   ACME 2,000 sh reported as $200: value in thousands by mistake (true value $200,000)
      Q1 2024  original   ACME 2,000 sh $220,000 | CIVIC bond, principal amount (excluded)
      Q1 2024  amendment  RESTATEMENT filed 20 Jun 2024: ACME 2,500 sh $275,000, replaces the original entirely
    Gamma Advisors (CIK 1003)
      Q1 2024  original   BOLT 300 sh $18,000
      Q1 2024  amendment  NEW HOLDINGS filed 1 Jul 2024: ACME 400 sh $44,000, added to the original
    Delta Fund (CIK 1004)
      Q1 2024  13F-NT notice: holdings reported by another manager, so no holdings rows
    Peer One to Four (CIK 1005-1008)
      both quarters: ACME at $100 then $110 a share, BOLT at $50 then $60, setting the consensus price;
      SPLIT 100 sh at $200, then 200 sh at $105 after its 2-for-1 split (a +5% return, not -47.5%)
      Peer One files Q1 on 1 Jun 2024, after the 15 May deadline
      Peer Two reports BOLT in Q1 at $60,000 a share: a suspect line, kept for holder counts, not for values

Usage:
    python tests/fixtures/make_fixtures.py
"""

from pathlib import Path

HERE = Path(__file__).resolve().parent

HEADERS = {
    "SUBMISSION": ["ACCESSION_NUMBER", "FILING_DATE", "SUBMISSIONTYPE", "CIK", "PERIODOFREPORT"],
    "COVERPAGE": ["ACCESSION_NUMBER", "REPORTCALENDARORQUARTER", "ISAMENDMENT", "AMENDMENTNO", "AMENDMENTTYPE",
                  "CONFDENIEDEXPIRED", "DATEDENIEDEXPIRED", "DATEREPORTED", "REASONFORNONCONFIDENTIALITY",
                  "FILINGMANAGER_NAME", "FILINGMANAGER_STREET1", "FILINGMANAGER_STREET2", "FILINGMANAGER_CITY",
                  "FILINGMANAGER_STATEORCOUNTRY", "FILINGMANAGER_ZIPCODE", "REPORTTYPE", "FORM13FFILENUMBER",
                  "CRDNUMBER", "SECFILENUMBER", "PROVIDEINFOFORINSTRUCTION5", "ADDITIONALINFORMATION"],
    "SUMMARYPAGE": ["ACCESSION_NUMBER", "OTHERINCLUDEDMANAGERSCOUNT", "TABLEENTRYTOTAL", "TABLEVALUETOTAL",
                    "ISCONFIDENTIALOMITTED"],
    "INFOTABLE": ["ACCESSION_NUMBER", "INFOTABLE_SK", "NAMEOFISSUER", "TITLEOFCLASS", "CUSIP", "FIGI", "VALUE",
                  "SSHPRNAMT", "SSHPRNAMTTYPE", "PUTCALL", "INVESTMENTDISCRETION", "OTHERMANAGER",
                  "VOTING_AUTH_SOLE", "VOTING_AUTH_SHARED", "VOTING_AUTH_NONE"],
}

ACME, BOLT, CIVIC = ("ACME CORP", "COM", "000000AA1"), ("BOLT INC", "CL A", "000000BB2"), ("CIVIC CO", "NOTE 5% 2030", "000000CC3")
SPLT = ("SPLIT CO", "COM", "000000DD4")   # splits 2-for-1 during Q1 2024: $200 a share, then $105
MANAGERS = {"1001": "ALPHA CAPITAL LLC", "1002": "BETA PARTNERS LP", "1003": "GAMMA ADVISORS INC", "1004": "DELTA FUND LLC",
            "1005": "PEER ONE LLC", "1006": "PEER TWO LLC", "1007": "PEER THREE LLC", "1008": "PEER FOUR LLC"}

# accession, filing date, submission type, cik, period, is amendment, amendment no, amendment type, report type, holdings
FILINGS = [
    ("0000001001-24-000001", "10-FEB-2024", "13F-HR", "1001", "31-DEC-2023", "", "", "", "13F HOLDINGS REPORT",
     [(ACME, 100000, 1000, "SH", ""), (BOLT, 25000, 500, "SH", ""), (SPLT, 20000, 100, "SH", "")]),
    ("0000001002-24-000001", "12-FEB-2024", "13F-HR", "1002", "31-DEC-2023", "", "", "", "13F HOLDINGS REPORT",
     [(ACME, 200, 2000, "SH", "")]),
    ("0000001001-24-000002", "14-MAY-2024", "13F-HR", "1001", "31-MAR-2024", "", "", "", "13F HOLDINGS REPORT",
     [(ACME, 110000, 1000, "SH", ""), (ACME, 55000, 500, "SH", ""), (BOLT, 3000, 50, "SH", "Put"),
      (SPLT, 21000, 200, "SH", "")]),
    ("0000001002-24-000002", "15-MAY-2024", "13F-HR", "1002", "31-MAR-2024", "", "", "", "13F HOLDINGS REPORT",
     [(ACME, 220000, 2000, "SH", ""), (CIVIC, 98000, 100000, "PRN", "")]),
    ("0000001003-24-000001", "10-MAY-2024", "13F-HR", "1003", "31-MAR-2024", "", "", "", "13F HOLDINGS REPORT",
     [(BOLT, 18000, 300, "SH", "")]),
    ("0000001004-24-000001", "13-MAY-2024", "13F-NT", "1004", "31-MAR-2024", "", "", "", "13F NOTICE", []),
    ("0000001002-24-000003", "20-JUN-2024", "13F-HR/A", "1002", "31-MAR-2024", "Y", "1", "RESTATEMENT",
     "13F HOLDINGS REPORT", [(ACME, 275000, 2500, "SH", "")]),
    ("0000001003-24-000002", "01-JUL-2024", "13F-HR/A", "1003", "31-MAR-2024", "Y", "1", "NEW HOLDINGS",
     "13F HOLDINGS REPORT", [(ACME, 44000, 400, "SH", "")]),
]
# Four peers that set the consensus price: ACME $100 at Q4 2023 and $110 at Q1 2024, BOLT $50 and $60.
for n, cik in enumerate(["1005", "1006", "1007", "1008"], start=1):
    q4 = [(ACME, 100 * 100 * n, 100 * n, "SH", ""), (BOLT, 50 * 200 * n, 200 * n, "SH", ""), (SPLT, 20000, 100, "SH", "")]
    q1 = [(ACME, 110 * 100 * n, 100 * n, "SH", ""), (BOLT, 60 * 200 * n, 200 * n, "SH", ""), (SPLT, 21000, 200, "SH", "")]
    if cik == "1006":
        q1[1] = (BOLT, 60_000 * 400, 400, "SH", "")   # value 1,000x too high for its shares: suspect, value not used
    q1_date = "01-JUN-2024" if cik == "1005" else "14-MAY-2024"  # Peer One files after the 15 May deadline
    FILINGS.append((f"000000{cik}-24-000001", "09-FEB-2024", "13F-HR", cik, "31-DEC-2023", "", "", "",
                    "13F HOLDINGS REPORT", q4))
    FILINGS.append((f"000000{cik}-24-000002", q1_date, "13F-HR", cik, "31-MAR-2024", "", "", "",
                    "13F HOLDINGS REPORT", q1))


def data_set_for(filing_date: str) -> str:
    month = filing_date[3:6]
    return {"FEB": "01jan2024-29feb2024", "MAY": "01mar2024-31may2024", "JUN": "01jun2024-31aug2024",
            "JUL": "01jun2024-31aug2024"}[month]


def main() -> None:
    rows: dict[str, dict[str, list[list[str]]]] = {}
    sk = 0
    for acc, fdate, stype, cik, period, is_amend, amend_no, amend_type, rtype, holdings in FILINGS:
        tables = rows.setdefault(data_set_for(fdate), {t: [] for t in HEADERS})
        tables["SUBMISSION"].append([acc, fdate, stype, cik, period])
        cover = dict.fromkeys(HEADERS["COVERPAGE"], "")
        cover.update(ACCESSION_NUMBER=acc, REPORTCALENDARORQUARTER=period, ISAMENDMENT=is_amend,
                     AMENDMENTNO=amend_no, AMENDMENTTYPE=amend_type, FILINGMANAGER_NAME=MANAGERS[cik],
                     FILINGMANAGER_STATEORCOUNTRY="NY", REPORTTYPE=rtype, PROVIDEINFOFORINSTRUCTION5="N")
        tables["COVERPAGE"].append([cover[c] for c in HEADERS["COVERPAGE"]])
        tables["SUMMARYPAGE"].append([acc, "0", str(len(holdings)), str(sum(h[1] for h in holdings)), "N"])
        for (name, title, cusip), value, amount, amount_type, putcall in holdings:
            sk += 1
            tables["INFOTABLE"].append([acc, str(sk), name, title, cusip, "", str(value), str(amount), amount_type,
                                        putcall, "SOLE", "", str(amount), "0", "0"])

    for data_set, tables in rows.items():
        out = HERE / data_set
        out.mkdir(exist_ok=True)
        for table, header in HEADERS.items():
            lines = ["\t".join(header)] + ["\t".join(r) for r in tables[table]]
            (out / f"{table}.tsv").write_text("\n".join(lines) + "\n")
    print(f"Wrote {len(FILINGS)} filings in {len(rows)} data sets to {HERE}")


if __name__ == "__main__":
    main()
