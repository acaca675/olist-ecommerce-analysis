"""
=======================================================================
OLIST PROJECT — Python + PostgreSQL Connection & Data Import
=======================================================================
File:    python/connection/01_db_setup.py
Platform: macOS (pip3 / python3)

Run order:
  1. Complete ALL terminal steps in the companion guide first
  2. Then:  python3 01_db_setup.py

What this script does:
  - Reads credentials from .env (never hardcoded)
  - Connects to PostgreSQL via SQLAlchemy
  - Imports all 9 CSV files into the olist schema
  - Validates final row counts against expected values
=======================================================================
"""

import os
import sys
import time
import pandas as pd
from pathlib import Path
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.exc import OperationalError

# -----------------------------------------------------------------------
# SECTION 1 — Load credentials from .env
# -----------------------------------------------------------------------
# .env must sit in the project ROOT (olist_project/.env)
# This line walks up the directory tree until it finds it.

# Resolve .env relative to THIS script's location
SCRIPT_DIR  = Path(__file__).resolve().parent          # …/python/connection/
PROJECT_ROOT = SCRIPT_DIR.parent.parent                 # …/olist_project/
ENV_FILE     = PROJECT_ROOT / ".env"

if not ENV_FILE.exists():
    print(f"❌  .env file not found at: {ENV_FILE}")
    print("    Create it by copying config/.env.template → .env")
    print("    Then fill in your PostgreSQL password.")
    sys.exit(1)

load_dotenv(dotenv_path=ENV_FILE)

DB_HOST     = os.getenv("DB_HOST",     "localhost")
DB_PORT     = os.getenv("DB_PORT",     "5432")
DB_NAME     = os.getenv("DB_NAME",     "olist_db")
DB_USER     = os.getenv("DB_USER",     "")          # No default — must be set in .env
DB_PASSWORD = os.getenv("DB_PASSWORD", "")

if not DB_USER:
    print("❌  DB_USER is empty in your .env file.")
    print("    On macOS, set DB_USER to your Mac system username.")
    print("    Find it by running:  whoami")
    sys.exit(1)

CONNECTION_STRING = (
    f"postgresql+psycopg2://{DB_USER}:{DB_PASSWORD}"
    f"@{DB_HOST}:{DB_PORT}/{DB_NAME}"
)

# -----------------------------------------------------------------------
# SECTION 2 — CSV data directory
# -----------------------------------------------------------------------
# Uses an absolute path derived from the project root.
# This means the script works regardless of which folder you cd into.

DATA_DIR = PROJECT_ROOT / "data" / "raw"

if not DATA_DIR.exists():
    print(f"❌  Data directory not found: {DATA_DIR}")
    print(f"    Create it and place your 9 CSV files inside:")
    print(f"    mkdir -p {DATA_DIR}")
    sys.exit(1)


# -----------------------------------------------------------------------
# SECTION 3 — Connection factory
# -----------------------------------------------------------------------

def get_engine():
    """Return a SQLAlchemy engine pointed at the olist schema."""
    engine = create_engine(
        CONNECTION_STRING,
        pool_size=5,
        max_overflow=10,
        pool_pre_ping=True,
        connect_args={"options": "-csearch_path=olist"},
    )
    return engine


def test_connection():
    """
    Try to connect and print the server version.
    Exits with a clear message if anything is wrong.
    """
    print("─" * 55)
    print("  Testing PostgreSQL connection…")
    print(f"  Host:     {DB_HOST}:{DB_PORT}")
    print(f"  Database: {DB_NAME}")
    print(f"  User:     {DB_USER}")
    print("─" * 55)

    try:
        engine = get_engine()
        with engine.connect() as conn:
            version = conn.execute(text("SELECT version();")).scalar()
            print(f"✅  Connected successfully.")
            print(f"    {version[:70]}…\n")
        return engine

    except OperationalError as e:
        err = str(e.orig) if hasattr(e, "orig") else str(e)
        print(f"\n❌  Connection failed.\n    Reason: {err}\n")

        if "password authentication" in err:
            print("→  Fix: Wrong DB_PASSWORD in your .env file.")
            print("   Run this in Terminal to reset it:")
            print(f'   psql -U {DB_USER} -c "ALTER USER {DB_USER} PASSWORD \'newpassword\';"')

        elif "role" in err and "does not exist" in err:
            print("→  Fix: Wrong DB_USER in your .env file.")
            print("   Your macOS username is the default PostgreSQL superuser.")
            print("   Find it with:  whoami")

        elif "database" in err and "does not exist" in err:
            print(f"→  Fix: Database '{DB_NAME}' has not been created yet.")
            print(f"   Run in Terminal:  createdb {DB_NAME}")

        elif "Connection refused" in err or "could not connect" in err:
            print("→  Fix: PostgreSQL is not running.")
            print("   Start it with:  brew services start postgresql@15")
            print("   Or check:       brew services list")

        sys.exit(1)


# -----------------------------------------------------------------------
# SECTION 4 — Import configuration (9 tables, in dependency order)
# -----------------------------------------------------------------------
# Dimension tables (no FK deps) come first.
# olist_orders must come before order_items / payments / reviews.

IMPORT_CONFIG = [
    {
        "file":   "olist_customers_dataset.csv",
        "table":  "olist_customers",
        "dtypes": {"customer_zip_code_prefix": str},
    },
    {
        "file":   "olist_sellers_dataset.csv",
        "table":  "olist_sellers",
        "dtypes": {"seller_zip_code_prefix": str},
    },
    {
        "file":   "olist_products_dataset.csv",
        "table":  "olist_products",
        "dtypes": None,
    },
    {
        "file":   "product_category_name_translation.csv",
        "table":  "product_category_name_translation",
        "dtypes": None,
    },
    {
        "file":   "olist_geolocation_dataset.csv",
        "table":  "olist_geolocation",
        "dtypes": {"geolocation_zip_code_prefix": str},
    },
    {
        "file":        "olist_orders_dataset.csv",
        "table":       "olist_orders",
        "dtypes":      None,
        "date_cols":   [
            "order_purchase_timestamp",
            "order_approved_at",
            "order_delivered_carrier_date",
            "order_delivered_customer_date",
            "order_estimated_delivery_date",
        ],
    },
    {
        "file":      "olist_order_items_dataset.csv",
        "table":     "olist_order_items",
        "dtypes":    None,
        "date_cols": ["shipping_limit_date"],
    },
    {
        "file":   "olist_order_payments_dataset.csv",
        "table":  "olist_order_payments",
        "dtypes": None,
    },
    {
        "file":      "olist_order_reviews_dataset.csv",
        "table":     "olist_order_reviews",
        "dtypes":    None,
        "date_cols": ["review_creation_date", "review_answer_timestamp"],
        "encoding":  "latin-1",   # Portuguese review text has accented chars
    },
]


# -----------------------------------------------------------------------
# SECTION 5 — Import one CSV file
# -----------------------------------------------------------------------

def import_csv(config: dict, engine) -> None:
    filepath = DATA_DIR / config["file"]
    table    = config["table"]

    if not filepath.exists():
        print(f"  ⚠️   File not found — skipping: {filepath.name}")
        print(f"       Expected location: {filepath}")
        return

    print(f"\n{'─'*55}")
    print(f"  File:  {config['file']}")
    print(f"  Table: olist.{table}")

    start = time.time()

    # --- Read CSV -------------------------------------------------------
    read_kwargs = {
        "dtype":      config.get("dtypes"),
        "encoding":   config.get("encoding", "utf-8"),
        "low_memory": False,
    }

    # parse_dates= was deprecated in pandas 2.0.
    # Use pd.to_datetime() after loading instead — works on all pandas versions.
    df = pd.read_csv(filepath, **read_kwargs)

    # Convert date columns explicitly (pandas 2.x safe)
    for col in config.get("date_cols", []):
        if col in df.columns:
            df[col] = pd.to_datetime(df[col], errors="coerce")

    # Normalise column names (strip spaces, lowercase)
    df.columns = df.columns.str.strip().str.lower()

    print(f"  Rows:    {len(df):,}")
    print(f"  Columns: {list(df.columns)}")

    # --- Write to PostgreSQL -------------------------------------------
    df.to_sql(
        name=table,
        con=engine,
        schema="olist",
        if_exists="replace",   # Drops & recreates table — safe for fresh import
        index=False,
        chunksize=5000,
        method="multi",
    )

    elapsed = time.time() - start
    print(f"  ✅  Done in {elapsed:.1f}s")


# -----------------------------------------------------------------------
# SECTION 6 — Run all imports
# -----------------------------------------------------------------------

def run_full_import():
    engine = test_connection()

    print("=" * 55)
    print("  OLIST DATABASE IMPORT — Starting")
    print("=" * 55)

    for config in IMPORT_CONFIG:
        import_csv(config, engine)

    print("\n" + "=" * 55)
    print("  ALL IMPORTS COMPLETE — Running validation…")
    print("=" * 55)

    validate_import(engine)


# -----------------------------------------------------------------------
# SECTION 7 — Validate row counts
# -----------------------------------------------------------------------

EXPECTED_COUNTS = {
    "olist_customers":                   99441,
    "olist_sellers":                      3095,
    "olist_products":                    32951,
    "product_category_name_translation":    71,
    "olist_geolocation":               1000163,
    "olist_orders":                      99441,
    "olist_order_items":                112650,
    "olist_order_payments":             103886,
    "olist_order_reviews":              104719,
}

def validate_import(engine):
    col_w = 45
    print(f"\n{'Table':<{col_w}} {'Expected':>10} {'Actual':>10}  Status")
    print("─" * 78)

    all_ok = True
    with engine.connect() as conn:
        for table, expected in EXPECTED_COUNTS.items():
            actual = conn.execute(
                text(f"SELECT COUNT(*) FROM olist.{table}")
            ).scalar()
            ok = actual == expected
            if not ok:
                all_ok = False
            status = "✅" if ok else f"⚠️  expected {expected:,}"
            print(f"{table:<{col_w}} {expected:>10,} {actual:>10,}  {status}")

    print()
    if all_ok:
        print("🎉  All row counts match. Database is ready for analysis.")
    else:
        print("⚠️   Some counts differ. This can happen if:")
        print("     • The CSV was re-downloaded and has minor version differences")
        print("     • The file was truncated during download")
        print("     • Re-run the import for the mismatched table only")


# -----------------------------------------------------------------------
# SECTION 8 — Reusable query helper (imported by other scripts)
# -----------------------------------------------------------------------

def run_query(sql: str, engine=None) -> pd.DataFrame:
    if engine is None:
        engine = get_engine()
    with engine.connect() as conn:
        return pd.read_sql_query(text(sql), conn)


# -----------------------------------------------------------------------
# Entry point
# -----------------------------------------------------------------------

if __name__ == "__main__":
    run_full_import()
