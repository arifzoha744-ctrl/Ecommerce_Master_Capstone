"""
04_reconcile.py
---------------
Reconciles key totals across the three stages of the pipeline:

    Raw CSV  ->  Python cleaned  ->  SQL Server star schema

Writes the result to reconciliation/reconciliation.md.

Any difference must be explained. Differences that come from a
deliberate cleaning decision are marked "Expected" with the reason.

Run from the project root:
    python python/04_reconcile.py
"""

import os
import pandas as pd
import pyodbc

# Use the same server name as 03_load_staging.py
SERVER = r"AP-CG-KL3-9172"
DATABASE = "OlistAnalytics"

CONN_STR = (
    f"DRIVER={{ODBC Driver 17 for SQL Server}};"
    f"SERVER={SERVER};DATABASE={DATABASE};Trusted_Connection=yes;"
)

RAW = "raw_data"
CLEAN = "python/cleaned"
OUT_DIR = "reconciliation"
os.makedirs(OUT_DIR, exist_ok=True)


# ----------------------------------------------------------------------
# RAW
# ----------------------------------------------------------------------
r_orders = pd.read_csv(f"{RAW}/olist_orders_dataset.csv")
r_items = pd.read_csv(f"{RAW}/olist_order_items_dataset.csv")
r_pay = pd.read_csv(f"{RAW}/olist_order_payments_dataset.csv")
r_rev = pd.read_csv(f"{RAW}/olist_order_reviews_dataset.csv")
r_cust = pd.read_csv(f"{RAW}/olist_customers_dataset.csv")
r_sell = pd.read_csv(f"{RAW}/olist_sellers_dataset.csv")
r_prod = pd.read_csv(f"{RAW}/olist_products_dataset.csv")

raw = {
    "Total orders": r_orders["order_id"].nunique(),
    "Delivered orders": (r_orders["order_status"] == "delivered").sum(),
    "Cancelled orders": (r_orders["order_status"] == "canceled").sum(),
    "Total order items": len(r_items),
    "Total customers (unique people)": r_cust["customer_unique_id"].nunique(),
    "Total sellers": r_sell["seller_id"].nunique(),
    "Total products": r_prod["product_id"].nunique(),
    "Total payment records": len(r_pay),
    "Total reviews": len(r_rev),
    "Merchandise value": round(r_items["price"].sum(), 2),
    "Freight value": round(r_items["freight_value"].sum(), 2),
    "Payment value": round(r_pay["payment_value"].sum(), 2),
}


# ----------------------------------------------------------------------
# PYTHON CLEANED
# ----------------------------------------------------------------------
c_orders = pd.read_csv(f"{CLEAN}/orders.csv")
c_items = pd.read_csv(f"{CLEAN}/order_items.csv")
c_pay = pd.read_csv(f"{CLEAN}/order_payments.csv")
c_rev = pd.read_csv(f"{CLEAN}/order_reviews.csv")
c_cust = pd.read_csv(f"{CLEAN}/customers.csv")
c_sell = pd.read_csv(f"{CLEAN}/sellers.csv")
c_prod = pd.read_csv(f"{CLEAN}/products.csv")

py = {
    "Total orders": c_orders["order_id"].nunique(),
    "Delivered orders": (c_orders["order_status"] == "delivered").sum(),
    "Cancelled orders": (c_orders["order_status"] == "canceled").sum(),
    "Total order items": len(c_items),
    "Total customers (unique people)": c_cust["customer_unique_id"].nunique(),
    "Total sellers": c_sell["seller_id"].nunique(),
    "Total products": c_prod["product_id"].nunique(),
    "Total payment records": len(c_pay),
    "Total reviews": len(c_rev),
    "Merchandise value": round(c_items["price"].sum(), 2),
    "Freight value": round(c_items["freight_value"].sum(), 2),
    "Payment value": round(c_pay["payment_value"].sum(), 2),
}


# ----------------------------------------------------------------------
# SQL SERVER (dw star schema)
# ----------------------------------------------------------------------
sql_queries = {
    "Total orders": "SELECT COUNT(DISTINCT order_id) FROM dw.fact_orders",
    "Delivered orders": "SELECT COUNT(*) FROM dw.fact_orders WHERE order_status = 'delivered'",
    "Cancelled orders": "SELECT COUNT(*) FROM dw.fact_orders WHERE order_status = 'canceled'",
    "Total order items": "SELECT COUNT(*) FROM dw.fact_order_items",
    "Total customers (unique people)": "SELECT COUNT(DISTINCT customer_unique_id) FROM dw.dim_customer",
    "Total sellers": "SELECT COUNT(*) FROM dw.dim_seller",
    "Total products": "SELECT COUNT(*) FROM dw.dim_product",
    "Total payment records": "SELECT COUNT(*) FROM dw.fact_payments",
    "Total reviews": "SELECT COUNT(*) FROM dw.fact_reviews",
    "Merchandise value": "SELECT SUM(price) FROM dw.fact_order_items",
    "Freight value": "SELECT SUM(freight_value) FROM dw.fact_order_items",
    "Payment value": "SELECT SUM(payment_value) FROM dw.fact_payments",
}

conn = pyodbc.connect(CONN_STR)
cur = conn.cursor()
sql = {}
for name, q in sql_queries.items():
    cur.execute(q)
    v = cur.fetchone()[0]
    sql[name] = round(float(v), 2) if name.endswith("value") else int(v)
cur.close()
conn.close()


# ----------------------------------------------------------------------
# Known, deliberate differences
# ----------------------------------------------------------------------
explanations = {
    "Total reviews": (
        "Python kept one review per order (the latest). 551 duplicate "
        "reviews on the same order were removed so reviews could be "
        "joined to orders without multiplying rows. See data quality "
        "report, issue 2."
    ),
}


# ----------------------------------------------------------------------
# Build report
# ----------------------------------------------------------------------
def fmt(name, v):
    if name.endswith("value"):
        return f"{v:,.2f}"
    return f"{v:,}"


rows = []
all_ok = True
for name in raw:
    a, b, c = raw[name], py[name], sql[name]
    if a == b == c:
        status = "Match"
    elif b == c and name in explanations:
        status = "Expected"
    else:
        status = "MISMATCH"
        all_ok = False
    rows.append((name, a, b, c, status))

lines = []
lines.append("# Reconciliation Report\n")
lines.append(
    "Key totals compared across the three stages of the pipeline: the raw "
    "source CSVs, the Python-cleaned output, and the SQL Server star schema.\n"
)
lines.append("Generated by `python/04_reconcile.py`.\n")
lines.append("| Metric | Raw CSV | Python cleaned | SQL Server | Status |")
lines.append("|---|---:|---:|---:|---|")
for name, a, b, c, status in rows:
    lines.append(f"| {name} | {fmt(name, a)} | {fmt(name, b)} | {fmt(name, c)} | {status} |")

lines.append("\n## Explanation of differences\n")
explained = [r for r in rows if r[4] == "Expected"]
if explained:
    for name, a, b, c, _ in explained:
        diff = a - b
        lines.append(f"**{name}** (difference of {fmt(name, diff)}): {explanations[name]}\n")
else:
    lines.append("No differences.\n")

lines.append("## Result\n")
if all_ok:
    lines.append(
        "All totals reconcile. Every difference between stages is the result "
        "of a documented, deliberate cleaning decision. No rows or value were "
        "lost or duplicated when loading into SQL Server, and all money totals "
        "match to the cent between the Python output and the star schema."
    )
else:
    lines.append("**One or more metrics do not reconcile and must be investigated.**")

report = "\n".join(lines) + "\n"

with open(f"{OUT_DIR}/reconciliation.md", "w", encoding="utf-8") as f:
    f.write(report)

# Console summary
print(f"{'Metric':<34}{'Raw':>16}{'Python':>16}{'SQL':>16}  Status")
print("-" * 90)
for name, a, b, c, status in rows:
    print(f"{name:<34}{fmt(name, a):>16}{fmt(name, b):>16}{fmt(name, c):>16}  {status}")
print("-" * 90)
print("ALL RECONCILED" if all_ok else "MISMATCH FOUND - INVESTIGATE")
print(f"\nReport written to {OUT_DIR}/reconciliation.md")
