import pandas as pd

orders    = pd.read_csv("raw_data/olist_orders_dataset.csv")
items     = pd.read_csv("raw_data/olist_order_items_dataset.csv")
payments  = pd.read_csv("raw_data/olist_order_payments_dataset.csv")
reviews   = pd.read_csv("raw_data/olist_order_reviews_dataset.csv")
customers = pd.read_csv("raw_data/olist_customers_dataset.csv")
products  = pd.read_csv("raw_data/olist_products_dataset.csv")
sellers   = pd.read_csv("raw_data/olist_sellers_dataset.csv")

print("--- KEY UNIQUENESS ---")
print("orders.order_id unique:", orders["order_id"].is_unique)
print("customers.customer_id unique:", customers["customer_id"].is_unique)
print("products.product_id unique:", products["product_id"].is_unique)
print("sellers.seller_id unique:", sellers["seller_id"].is_unique)
print("items dupes on (order_id, order_item_id):",
      items.duplicated(["order_id", "order_item_id"]).sum())
print("payments dupes on (order_id, payment_sequential):",
      payments.duplicated(["order_id", "payment_sequential"]).sum())
print("reviews.review_id unique:", reviews["review_id"].is_unique)
print("reviews.order_id unique:", reviews["order_id"].is_unique)

print("\n--- REAL CUSTOMERS ---")
print("customer_id count:", customers["customer_id"].nunique())
print("customer_unique_id count:", customers["customer_unique_id"].nunique())

print("\n--- ORPHANS (should all be 0) ---")
print("items with no order:", (~items["order_id"].isin(orders["order_id"])).sum())
print("payments with no order:", (~payments["order_id"].isin(orders["order_id"])).sum())
print("reviews with no order:", (~reviews["order_id"].isin(orders["order_id"])).sum())
print("items with no product:", (~items["product_id"].isin(products["product_id"])).sum())
print("items with no seller:", (~items["seller_id"].isin(sellers["seller_id"])).sum())
print("orders with no customer:", (~orders["customer_id"].isin(customers["customer_id"])).sum())

print("\n--- COVERAGE ---")
print("orders with no payment:", (~orders["order_id"].isin(payments["order_id"])).sum())
print("orders with no review:", (~orders["order_id"].isin(reviews["order_id"])).sum())
print("orders with no items:", (~orders["order_id"].isin(items["order_id"])).sum())

print("\n--- DATE RANGE ---")
d = pd.to_datetime(orders["order_purchase_timestamp"])
print("First order:", d.min(), "| Last order:", d.max())

print("\n--- ORDER STATUS ---")
print(orders["order_status"].value_counts())
