"""
03_load_staging.py
------------------
Loads the cleaned CSV files from python/cleaned/ into SQL Server
staging tables (stg schema).

Reproducible: drops and rebuilds every staging table on each run,
so the load can be repeated without manual cleanup.

Uses pyodbc directly (no sqlalchemy required).

Run from the project root:
    python python/03_load_staging.py
"""

import pandas as pd
import pyodbc

# ----------------------------------------------------------------------
# CONNECTION
# ----------------------------------------------------------------------
# If "localhost\\SQLEXPRESS" fails, try "localhost" or "." instead.

SERVER = r"AP-CG-KL3-9172"
DATABASE = "OlistAnalytics"

CONN_STR = (
    f"DRIVER={{ODBC Driver 17 for SQL Server}};"
    f"SERVER={SERVER};"
    f"DATABASE={DATABASE};"
    f"Trusted_Connection=yes;"
)

SRC = "python/cleaned"


# ----------------------------------------------------------------------
# TABLE DEFINITIONS
# ----------------------------------------------------------------------
# Types are declared explicitly rather than inferred, so that keys are
# sized correctly and money columns land as DECIMAL rather than FLOAT.

TABLES = {
    "stg_orders": {
        "file": "orders.csv",
        "ddl": """
            CREATE TABLE stg.stg_orders (
                order_id                      CHAR(32),
                customer_id                   CHAR(32),
                order_status                  VARCHAR(20),
                order_purchase_timestamp      DATETIME2,
                order_approved_at             DATETIME2,
                order_delivered_carrier_date  DATETIME2,
                order_delivered_customer_date DATETIME2,
                order_estimated_delivery_date DATETIME2,
                delivery_days                 INT,
                estimated_days                INT,
                delivery_delay_days           INT,
                is_delivered                  BIT,
                is_cancelled                  BIT,
                is_late                       BIT
            )
        """,
    },
    "stg_order_items": {
        "file": "order_items.csv",
        "ddl": """
            CREATE TABLE stg.stg_order_items (
                order_id            CHAR(32),
                order_item_id       INT,
                product_id          CHAR(32),
                seller_id           CHAR(32),
                shipping_limit_date DATETIME2,
                price               DECIMAL(12,2),
                freight_value       DECIMAL(12,2)
            )
        """,
    },
    "stg_order_payments": {
        "file": "order_payments.csv",
        "ddl": """
            CREATE TABLE stg.stg_order_payments (
                order_id             CHAR(32),
                payment_sequential   INT,
                payment_type         VARCHAR(30),
                payment_installments INT,
                payment_value        DECIMAL(12,2)
            )
        """,
    },
    "stg_order_reviews": {
        "file": "order_reviews.csv",
        "ddl": """
            CREATE TABLE stg.stg_order_reviews (
                review_id               CHAR(32),
                order_id                CHAR(32),
                review_score            INT,
                review_comment_title    NVARCHAR(200),
                review_comment_message  NVARCHAR(MAX),
                review_creation_date    DATETIME2,
                review_answer_timestamp DATETIME2
            )
        """,
    },
    "stg_customers": {
        "file": "customers.csv",
        "ddl": """
            CREATE TABLE stg.stg_customers (
                customer_id              CHAR(32),
                customer_unique_id       CHAR(32),
                customer_zip_code_prefix INT,
                customer_city            NVARCHAR(100),
                customer_state           CHAR(2)
            )
        """,
    },
    "stg_sellers": {
        "file": "sellers.csv",
        "ddl": """
            CREATE TABLE stg.stg_sellers (
                seller_id              CHAR(32),
                seller_zip_code_prefix INT,
                seller_city            NVARCHAR(100),
                seller_state           CHAR(2)
            )
        """,
    },
    "stg_products": {
        "file": "products.csv",
        "ddl": """
            CREATE TABLE stg.stg_products (
                product_id                    CHAR(32),
                product_category_name         NVARCHAR(100),
                product_name_length           FLOAT,
                product_description_length    FLOAT,
                product_photos_qty            FLOAT,
                product_weight_g              FLOAT,
                product_length_cm             FLOAT,
                product_height_cm             FLOAT,
                product_width_cm              FLOAT,
                product_category_name_english NVARCHAR(100)
            )
        """,
    },
    "stg_geolocation": {
        "file": "geolocation.csv",
        "ddl": """
            CREATE TABLE stg.stg_geolocation (
                geolocation_zip_code_prefix INT,
                geolocation_lat             FLOAT,
                geolocation_lng             FLOAT,
                geolocation_city            NVARCHAR(100),
                geolocation_state           CHAR(2)
            )
        """,
    },
}


def load_table(cursor, table_name, spec):
    """Drop, recreate and populate one staging table."""
    df = pd.read_csv(f"{SRC}/{spec['file']}")

    # Pandas NaN is not understood by SQL Server. Convert to None (NULL).
    df = df.astype(object).where(pd.notnull(df), None)

    cursor.execute(f"IF OBJECT_ID('stg.{table_name}', 'U') IS NOT NULL DROP TABLE stg.{table_name}")
    cursor.execute(spec["ddl"])
    cursor.commit()

    cols = list(df.columns)
    placeholders = ", ".join("?" * len(cols))
    col_list = ", ".join(cols)
    insert_sql = f"INSERT INTO stg.{table_name} ({col_list}) VALUES ({placeholders})"

    cursor.fast_executemany = True
    rows = df.values.tolist()

    # Insert in chunks so a large table does not exhaust memory
    CHUNK = 10000
    for i in range(0, len(rows), CHUNK):
        cursor.executemany(insert_sql, rows[i:i + CHUNK])
        cursor.commit()

    return len(df)


def main():
    print(f"Connecting to {SERVER} / {DATABASE} ...")
    conn = pyodbc.connect(CONN_STR)
    cursor = conn.cursor()
    print("Connected.\n")

    total = 0
    for table_name, spec in TABLES.items():
        count = load_table(cursor, table_name, spec)
        total += count
        print(f"loaded stg.{table_name:<22} {count:>9,} rows")

    print("\n" + "=" * 55)
    print(f"{'TOTAL':<28} {total:>9,} rows")
    print("=" * 55)

    # Verify by reading the counts back out of SQL Server
    print("\nVerifying row counts from SQL Server:")
    for table_name in TABLES:
        cursor.execute(f"SELECT COUNT(*) FROM stg.{table_name}")
        print(f"  stg.{table_name:<22} {cursor.fetchone()[0]:>9,}")

    cursor.close()
    conn.close()
    print("\nStaging load complete.")


if __name__ == "__main__":
    main()
