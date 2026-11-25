"""
Build pipeline:
  1. load the CSV files into a SQLite database (outputs/auto_sales.db)
  2. run the data-quality checks
  3. run every KPI query in sql/ and export the results to outputs/*.csv
  4. write the interactive dashboard (dashboard/index.html)

Usage:
    python data/generate_data.py
    python analysis/build.py
"""

import json
import sqlite3
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw"
SQL = ROOT / "sql"
OUT = ROOT / "outputs"
DASH = ROOT / "dashboard"

TABLES = ["dim_dealer", "dim_model", "dim_model_energy", "fact_orders",
          "fact_registrations", "fact_stock", "fact_targets", "fact_market"]


def sql(name: str) -> str:
    return (SQL / name).read_text(encoding="utf-8")


def load(con: sqlite3.Connection) -> None:
    con.executescript(sql("01_schema.sql"))
    for t in TABLES:
        df = pd.read_csv(RAW / f"{t}.csv")
        df.to_sql(t, con, if_exists="append", index=False)
    # the scorecard is reused by the quartile and alert queries
    con.execute("DROP VIEW IF EXISTS v_dealer_scorecard")
    con.execute("CREATE VIEW v_dealer_scorecard AS " + sql("04_dealer_scorecard_360.sql").split(";")[0])
    con.commit()


def run(con, name: str) -> pd.DataFrame:
    return pd.read_sql_query(sql(name), con)


def main() -> None:
    OUT.mkdir(exist_ok=True)
    db = OUT / "auto_sales.db"
    db.unlink(missing_ok=True)
    con = sqlite3.connect(db)
    load(con)

    dq = run(con, "02_data_quality_checks.sql")
    print(dq.to_string(index=False))
    if dq.issues.sum():
        raise SystemExit("Data-quality checks failed")

    results = {}
    for f in sorted(SQL.glob("0[3-8]_*.sql")):
        df = run(con, f.name)
        df.to_csv(OUT / f"{f.stem}.csv", index=False)
        results[f.stem] = df
        print(f"{f.name}: {len(df)} rows")

    dealers = pd.read_sql_query("SELECT * FROM dim_dealer", con)
    monthly = run(con, "09_dashboard_extract.sql")
    mix = run(con, "10_dashboard_mix_extract.sql")
    scorecard = results["04_dealer_scorecard_360"].merge(
        results["05_dealer_quartiles"][["dealer_id", "quartile", "classification"]], on="dealer_id")
    share = results["07_market_share_by_segment"]

    payload = {
        "period": {"start": "2025-10-01", "end": "2026-09-30"},
        "dealers": dealers.to_dict("records"),
        "monthly": monthly.values.tolist(),
        "monthly_cols": list(monthly.columns),
        "mix": mix.values.tolist(),
        "scorecard": scorecard.to_dict("records"),
        "market_share": share.to_dict("records"),
    }
    template = (DASH / "template.html").read_text(encoding="utf-8")
    html = template.replace("/*__DATA__*/null", json.dumps(payload, separators=(",", ":")))
    (DASH / "index.html").write_text(html, encoding="utf-8")
    print(f"dashboard written: {DASH / 'index.html'}")


if __name__ == "__main__":
    main()
