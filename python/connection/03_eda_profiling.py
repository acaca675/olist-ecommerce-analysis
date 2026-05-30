"""
=======================================================================
OLIST PROJECT — Exploratory Data Analysis (EDA) in Python
=======================================================================
File:    python/etl/03_eda_profiling.py
Purpose: Data quality checks, null analysis, distribution summaries,
         and key dataset facts — run this BEFORE writing SQL analytics.

Best run as: Jupyter Notebook cell-by-cell for interactive exploration
=======================================================================
"""

import sys
import pandas as pd
import numpy as np
from pathlib import Path

sys.path.append(str(Path(__file__).parent.parent / "connection"))
from db_setup import get_engine, run_query

engine = get_engine()


# -----------------------------------------------------------------------
# 1. NULL PROFILE — Find data quality issues
# -----------------------------------------------------------------------

def null_profile(table: str) -> pd.DataFrame:
    """Return null count and percentage for every column in a table."""
    sql = f"""
        SELECT column_name, data_type
        FROM information_schema.columns
        WHERE table_schema = 'olist' AND table_name = '{table}'
        ORDER BY ordinal_position
    """
    cols_df = run_query(sql, engine)
    cols = list(cols_df["column_name"])

    null_checks = ", ".join(
        [f"SUM(CASE WHEN {c} IS NULL THEN 1 ELSE 0 END) AS {c}_nulls" for c in cols]
    )
    total_sql = f"SELECT COUNT(*) AS total, {null_checks} FROM olist.{table}"
    result = run_query(total_sql, engine)

    total = result["total"].iloc[0]
    rows = []
    for col in cols:
        null_count = result.get(f"{col}_nulls", pd.Series([0])).iloc[0]
        rows.append({
            "column":    col,
            "data_type": cols_df.loc[cols_df["column_name"] == col, "data_type"].values[0],
            "null_count": null_count,
            "null_pct":   round(null_count / total * 100, 2) if total > 0 else 0,
            "total_rows": total,
        })
    return pd.DataFrame(rows)


# Example usage:
# print(null_profile("olist_orders").to_string())


# -----------------------------------------------------------------------
# 2. ORDER STATUS DISTRIBUTION
# -----------------------------------------------------------------------

def order_status_summary():
    sql = """
        SELECT
            order_status,
            COUNT(*) AS count,
            ROUND(COUNT(*)::NUMERIC / SUM(COUNT(*)) OVER () * 100, 2) AS pct
        FROM olist.olist_orders
        GROUP BY order_status
        ORDER BY count DESC
    """
    df = run_query(sql, engine)
    print("=== Order Status Distribution ===")
    print(df.to_string(index=False))
    print()
    print("Business note: Only 'delivered' orders should be used for")
    print("  delivery time / review / revenue analysis.")
    return df


# -----------------------------------------------------------------------
# 3. DATE RANGE & COVERAGE
# -----------------------------------------------------------------------

def date_coverage():
    sql = """
        SELECT
            MIN(order_purchase_timestamp)::DATE AS earliest_order,
            MAX(order_purchase_timestamp)::DATE AS latest_order,
            COUNT(DISTINCT DATE_TRUNC('month', order_purchase_timestamp)) AS months_covered,
            COUNT(*) AS total_orders,
            COUNT(CASE WHEN EXTRACT(YEAR FROM order_purchase_timestamp) = 2016 THEN 1 END) AS orders_2016,
            COUNT(CASE WHEN EXTRACT(YEAR FROM order_purchase_timestamp) = 2017 THEN 1 END) AS orders_2017,
            COUNT(CASE WHEN EXTRACT(YEAR FROM order_purchase_timestamp) = 2018 THEN 1 END) AS orders_2018
        FROM olist.olist_orders
        WHERE order_purchase_timestamp IS NOT NULL
    """
    df = run_query(sql, engine)
    print("=== Dataset Date Coverage ===")
    print(df.to_string(index=False))
    print()
    print("Note: 2016 data is only 3 months (Oct-Dec). Focus analysis on 2017-2018.")
    return df


# -----------------------------------------------------------------------
# 4. CUSTOMER ID EXPLAINED
# -----------------------------------------------------------------------

def customer_id_analysis():
    """
    Demonstrates the difference between customer_id and customer_unique_id.
    This is the most common mistake beginners make with this dataset.
    """
    sql = """
        SELECT
            COUNT(customer_id)        AS total_customer_id_rows,
            COUNT(DISTINCT customer_id) AS distinct_customer_ids,
            COUNT(DISTINCT customer_unique_id) AS distinct_unique_customers,
            COUNT(customer_id) - COUNT(DISTINCT customer_unique_id) AS extra_ids_due_to_repeat_buyers
        FROM olist.olist_customers
    """
    df = run_query(sql, engine)
    print("=== customer_id vs customer_unique_id ===")
    print(df.to_string(index=False))
    print()
    print("Explanation:")
    print("  customer_id       = one ID per ORDER (a new ID is generated each purchase)")
    print("  customer_unique_id = one ID per PERSON (stable across all purchases)")
    print()
    print("⚠️  Always use customer_unique_id for:")
    print("  • Repeat buyer analysis")
    print("  • Customer lifetime value (CLV)")
    print("  • Retention rates")
    print("  • RFM segmentation")
    print()
    print("✅ customer_id is fine for: joining orders → customers table only")

    # Find actual repeat buyers
    repeat_sql = """
        SELECT
            order_count,
            COUNT(*) AS customers_with_n_orders,
            ROUND(COUNT(*)::NUMERIC / SUM(COUNT(*)) OVER () * 100, 2) AS pct
        FROM (
            SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS order_count
            FROM olist.olist_customers c
            JOIN olist.olist_orders    o ON c.customer_id = o.customer_id
            WHERE o.order_status NOT IN ('canceled','unavailable')
            GROUP BY c.customer_unique_id
        ) sub
        GROUP BY order_count
        ORDER BY order_count
    """
    repeat_df = run_query(repeat_sql, engine)
    print("\n=== Order Frequency Distribution ===")
    print(repeat_df.to_string(index=False))
    return df, repeat_df


# -----------------------------------------------------------------------
# 5. PAYMENT DISTRIBUTION
# -----------------------------------------------------------------------

def payment_analysis():
    sql = """
        SELECT
            payment_type,
            COUNT(*) AS transaction_count,
            ROUND(SUM(payment_value)::NUMERIC, 2) AS total_value,
            ROUND(AVG(payment_value)::NUMERIC, 2) AS avg_value,
            ROUND(AVG(payment_installments)::NUMERIC, 1) AS avg_installments,
            ROUND(COUNT(*)::NUMERIC / SUM(COUNT(*)) OVER () * 100, 1) AS pct_of_transactions
        FROM olist.olist_order_payments
        GROUP BY payment_type
        ORDER BY total_value DESC
    """
    df = run_query(sql, engine)
    print("=== Payment Type Analysis ===")
    print(df.to_string(index=False))
    return df


# -----------------------------------------------------------------------
# 6. TOP STATES BY ORDER VOLUME
# -----------------------------------------------------------------------

def geo_summary():
    sql = """
        SELECT
            c.customer_state,
            COUNT(DISTINCT o.order_id)          AS total_orders,
            COUNT(DISTINCT c.customer_unique_id) AS unique_customers,
            ROUND(SUM(p.payment_value)::NUMERIC, 0) AS total_gmv,
            ROUND(AVG(p.payment_value)::NUMERIC, 2) AS avg_order_value
        FROM olist.olist_orders           o
        JOIN olist.olist_customers        c ON o.customer_id = c.customer_id
        JOIN olist.olist_order_payments   p ON o.order_id    = p.order_id
        WHERE o.order_status NOT IN ('canceled','unavailable')
        GROUP BY c.customer_state
        ORDER BY total_orders DESC
        LIMIT 10
    """
    df = run_query(sql, engine)
    print("=== Top 10 States by Order Volume ===")
    print(df.to_string(index=False))
    print()
    print("Note: SP (São Paulo) alone accounts for ~40%+ of all orders.")
    print("This geographic concentration is an important business finding.")
    return df


# -----------------------------------------------------------------------
# RUN ALL EDA CHECKS
# -----------------------------------------------------------------------

if __name__ == "__main__":
    print("=" * 60)
    print("OLIST EDA — Data Profiling Report")
    print("=" * 60)
    print()
    order_status_summary()
    print()
    date_coverage()
    print()
    customer_id_analysis()
    print()
    payment_analysis()
    print()
    geo_summary()
