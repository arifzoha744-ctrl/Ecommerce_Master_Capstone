"""
02_clean.py
-----------
Reproducible data preparation for the Olist E-Commerce Capstone.

Reads raw CSVs from raw_data/, applies the fixes identified during profiling,
and writes cleaned files to python/cleaned/.

Every transformation below is driven by a specific finding in
profiling/profiling_summary.md. Nothing is cleaned "just in case".

Run from the project root:
    python python/02_clean.py
"""

import os
import pandas as pd

RAW = "raw_data"
OUT = "python/cleaned"
os.makedirs(OUT, exist_ok=True)

log = []


def note(msg):
    """Record a decision so it can be reported and defended later."""
    print(msg)
    log.append(msg)


# ----------------------------------------------------------------------
# 1. ORDERS
# ----------------------------------------------------------------------
# Finding: all 5 date columns are stored as text.
# Finding: 160 / 1,783 / 2,965 nulls across the lifecycle dates.
#          These are orders that never reached that stage. They are real
#          information, NOT missing data, so they are left as null.

orders = pd.read_csv(f"{RAW}/olist_orders_dataset.csv")

date_cols = [
    "order_purchase_timestamp",
    "order_approved_at",
    "order_delivered_carrier_date",
    "order_delivered_customer_date",
    "order_estimated_delivery_date",
]
for c in date_cols:
    orders[c] = pd.to_datetime(orders[c], errors="coerce")

note(f"orders: converted {len(date_cols)} text columns to datetime")
note("orders: lifecycle date nulls retained (they mean the stage never happened)")

# Derived delivery metrics, calculated once here so SQL and Power BI agree.
orders["delivery_days"] = (
    orders["order_delivered_customer_date"] - orders["order_purchase_timestamp"]
).dt.days

orders["estimated_days"] = (
    orders["order_estimated_delivery_date"] - orders["order_purchase_timestamp"]
).dt.days

# Positive = late, negative = early. Null when never delivered.
orders["delivery_delay_days"] = (
    orders["order_delivered_customer_date"] - orders["order_estimated_delivery_date"]
).dt.days

orders["is_delivered"] = (orders["order_status"] == "delivered").astype(int)
orders["is_cancelled"] = (orders["order_status"] == "canceled").astype(int)

# On-time / late only defined for orders that were actually delivered.
orders["is_late"] = (orders["delivery_delay_days"] > 0).astype("Int64")
orders.loc[orders["order_delivered_customer_date"].isna(), "is_late"] = pd.NA

note("orders: added delivery_days, estimated_days, delivery_delay_days, is_late")
note("orders: is_late left null for undelivered orders rather than assumed False")


# ----------------------------------------------------------------------
# 2. ORDER ITEMS
# ----------------------------------------------------------------------
# Finding: no nulls, no duplicates, key (order_id + order_item_id) is clean.
# Only fix needed is the date column type.
# price and freight_value are kept separate - they are different money.

items = pd.read_csv(f"{RAW}/olist_order_items_dataset.csv")
items["shipping_limit_date"] = pd.to_datetime(items["shipping_limit_date"], errors="coerce")

note(f"order_items: {len(items):,} rows, clean. Converted shipping_limit_date")
note("order_items: price and freight_value kept as separate measures")


# ----------------------------------------------------------------------
# 3. PAYMENTS
# ----------------------------------------------------------------------
# Finding: clean, but grain is one payment transaction, not one order.
# Kept at its own grain. payment_value is NOT merchandise value.

payments = pd.read_csv(f"{RAW}/olist_order_payments_dataset.csv")

# installments of 0 is not meaningful - treat single payment as 1
zero_inst = (payments["payment_installments"] == 0).sum()
payments.loc[payments["payment_installments"] == 0, "payment_installments"] = 1
note(f"payments: corrected {zero_inst} rows with 0 installments to 1")

not_defined = (payments["payment_type"] == "not_defined").sum()
note(f"payments: {not_defined} rows have payment_type 'not_defined' - retained and flagged")


# ----------------------------------------------------------------------
# 4. REVIEWS
# ----------------------------------------------------------------------
# Finding: review_id is NOT unique and order_id is NOT unique.
# Decision: keep ONE review per order - the most recent one - so that
# reviews can be joined to orders without multiplying rows.
# Reason: the latest review represents the customer's final position.

reviews = pd.read_csv(f"{RAW}/olist_order_reviews_dataset.csv")
before = len(reviews)

for c in ["review_creation_date", "review_answer_timestamp"]:
    reviews[c] = pd.to_datetime(reviews[c], errors="coerce")

reviews = reviews.sort_values("review_creation_date", ascending=False)
reviews = reviews.drop_duplicates(subset="order_id", keep="first")

note(f"reviews: reduced {before:,} to {len(reviews):,} rows - one review per order (latest kept)")
note("reviews: comment title/message nulls retained, they simply mean no text was written")


# ----------------------------------------------------------------------
# 5. CUSTOMERS
# ----------------------------------------------------------------------
# Finding: clean, but customer_id is per-order and customer_unique_id
# is the real person (99,441 vs 96,096).

customers = pd.read_csv(f"{RAW}/olist_customers_dataset.csv")
customers["customer_city"] = customers["customer_city"].str.strip().str.title()
customers["customer_state"] = customers["customer_state"].str.strip().str.upper()

note("customers: standardised city and state text casing")
note("customers: customer_unique_id will be used for all customer counting")


# ----------------------------------------------------------------------
# 6. SELLERS
# ----------------------------------------------------------------------

sellers = pd.read_csv(f"{RAW}/olist_sellers_dataset.csv")
sellers["seller_city"] = sellers["seller_city"].str.strip().str.title()
sellers["seller_state"] = sellers["seller_state"].str.strip().str.upper()

note("sellers: standardised city and state text casing")


# ----------------------------------------------------------------------
# 7. PRODUCTS  (+ category translation)
# ----------------------------------------------------------------------
# Finding: 610 products have no category name.
# Decision: label them 'unknown' rather than dropping them, because their
# order items still carry real revenue that must not disappear.

products = pd.read_csv(f"{RAW}/olist_products_dataset.csv")
translation = pd.read_csv(f"{RAW}/product_category_name_translation.csv")

# Fix the misspelled source column names
products = products.rename(columns={
    "product_name_lenght": "product_name_length",
    "product_description_lenght": "product_description_length",
})

missing_cat = products["product_category_name"].isna().sum()
products["product_category_name"] = products["product_category_name"].fillna("unknown")

products = products.merge(translation, on="product_category_name", how="left")
products["product_category_name_english"] = (
    products["product_category_name_english"].fillna("Unknown")
)

untranslated = (products["product_category_name_english"] == "Unknown").sum()

note(f"products: fixed 2 misspelled column names in source")
note(f"products: {missing_cat} missing categories labelled 'unknown' (rows kept, revenue preserved)")
note(f"products: {untranslated} products end with English category 'Unknown'")


# ----------------------------------------------------------------------
# 8. GEOLOCATION
# ----------------------------------------------------------------------
# Finding: 1,000,163 rows with 261,831 exact duplicates, many rows per zip.
# Decision: collapse to ONE row per zip prefix using the average coordinate
# and the most common city/state. Without this it is a many-to-many join
# and would multiply every customer and seller row.

geo = pd.read_csv(f"{RAW}/olist_geolocation_dataset.csv")
before = len(geo)
geo = geo.drop_duplicates()
after_dedupe = len(geo)

geo_clean = (
    geo.groupby("geolocation_zip_code_prefix")
    .agg(
        geolocation_lat=("geolocation_lat", "mean"),
        geolocation_lng=("geolocation_lng", "mean"),
        geolocation_city=("geolocation_city", lambda s: s.mode().iloc[0]),
        geolocation_state=("geolocation_state", lambda s: s.mode().iloc[0]),
    )
    .reset_index()
)

geo_clean["geolocation_city"] = geo_clean["geolocation_city"].str.strip().str.title()
geo_clean["geolocation_state"] = geo_clean["geolocation_state"].str.strip().str.upper()

note(f"geolocation: {before:,} rows -> {after_dedupe:,} after dedupe -> {len(geo_clean):,} after aggregation")
note("geolocation: one row per zip prefix (mean coordinate, modal city/state) to remove many-to-many")


# ----------------------------------------------------------------------
# SAVE
# ----------------------------------------------------------------------

outputs = {
    "orders": orders,
    "order_items": items,
    "order_payments": payments,
    "order_reviews": reviews,
    "customers": customers,
    "sellers": sellers,
    "products": products,
    "geolocation": geo_clean,
}

print("\n" + "=" * 70)
for name, df in outputs.items():
    path = f"{OUT}/{name}.csv"
    df.to_csv(path, index=False)
    print(f"saved {path:<38} {len(df):>9,} rows")

with open("python/cleaning_log.txt", "w") as f:
    f.write("Data Preparation Log\n")
    f.write("=" * 70 + "\n\n")
    for line in log:
        f.write(line + "\n")

print("=" * 70)
print("Decision log written to python/cleaning_log.txt")
