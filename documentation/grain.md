# Source Data Grain

What one row represents in each source file.

| File | One row represents | Key | Rows |
|---|---|---|---|
| olist_orders_dataset | One order placed by one customer | order_id | 99,441 |
| olist_order_items_dataset | One product line inside one order | order_id + order_item_id | 112,650 |
| olist_order_payments_dataset | One payment transaction against one order | order_id + payment_sequential | 103,886 |
| olist_order_reviews_dataset | One review submitted for one order | review_id (not reliably unique) | 99,224 |
| olist_customers_dataset | One customer record created for one order | customer_id | 99,441 |
| olist_products_dataset | One product | product_id | 32,951 |
| olist_sellers_dataset | One seller | seller_id | 3,095 |
| olist_geolocation_dataset | One geographic coordinate point for a zip prefix | none (many rows per zip) | 1,000,163 |
| product_category_name_translation | One category name mapping, Portuguese to English | product_category_name | 71 |

## Why grain matters here

Three tables sit at different levels of detail against the same order:

- orders is one row per order
- order_items is one row per item, so an order with 3 products has 3 rows
- payments is one row per transaction, so an order paid in 2 parts has 2 rows

Joining these together produces a row count equal to items multiplied by
payments for each order. An order with 3 items and 2 payments becomes 6 rows,
and any sum of price, freight or payment_value is then inflated.

Because of this the solution keeps four separate fact tables, each at its own
grain, connected through shared dimensions rather than joined into one table.

## Where each measure belongs

| Measure | Correct source | Grain |
|---|---|---|
| Merchandise value (price) | order_items | item |
| Freight value | order_items | item |
| Payment value | order_payments | payment transaction |
| Order count | orders | order |
| Customer count | customers via customer_unique_id | person |
| Review score | order_reviews | review |
| Delivery timings | orders | order |

A measure must only ever be summed from its own table.