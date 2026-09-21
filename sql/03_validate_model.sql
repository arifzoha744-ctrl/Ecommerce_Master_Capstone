/* =====================================================================
   03_validate_model.sql
   ---------------------------------------------------------------------
   Proves the star schema is correct:
     1. No rows were lost or duplicated between staging and dw
     2. Money totals are identical between staging and dw
     3. Every fact table is unique at its declared grain
     4. Demonstrates the fan-out error the model is designed to avoid

   Run AFTER 02_create_facts.sql.
   ===================================================================== */

USE OlistAnalytics;
GO

SET NOCOUNT ON;
GO


/* ---------------------------------------------------------------------
   CHECK 1 - Row counts: staging vs dw
   Every Difference should be 0.
   --------------------------------------------------------------------- */
SELECT 'orders' AS entity,
       (SELECT COUNT(*) FROM stg.stg_orders)         AS staging_rows,
       (SELECT COUNT(*) FROM dw.fact_orders)          AS dw_rows
UNION ALL
SELECT 'order_items',
       (SELECT COUNT(*) FROM stg.stg_order_items),
       (SELECT COUNT(*) FROM dw.fact_order_items)
UNION ALL
SELECT 'payments',
       (SELECT COUNT(*) FROM stg.stg_order_payments),
       (SELECT COUNT(*) FROM dw.fact_payments)
UNION ALL
SELECT 'reviews',
       (SELECT COUNT(*) FROM stg.stg_order_reviews),
       (SELECT COUNT(*) FROM dw.fact_reviews)
UNION ALL
SELECT 'customers',
       (SELECT COUNT(*) FROM stg.stg_customers),
       (SELECT COUNT(*) FROM dw.dim_customer)
UNION ALL
SELECT 'sellers',
       (SELECT COUNT(*) FROM stg.stg_sellers),
       (SELECT COUNT(*) FROM dw.dim_seller)
UNION ALL
SELECT 'products',
       (SELECT COUNT(*) FROM stg.stg_products),
       (SELECT COUNT(*) FROM dw.dim_product);
GO


/* ---------------------------------------------------------------------
   CHECK 2 - Money totals: staging vs dw
   Every Difference should be 0.00.
   --------------------------------------------------------------------- */
SELECT 'merchandise_value (price)' AS measure,
       (SELECT SUM(price)         FROM stg.stg_order_items)    AS staging_total,
       (SELECT SUM(price)         FROM dw.fact_order_items)    AS dw_total
UNION ALL
SELECT 'freight_value',
       (SELECT SUM(freight_value) FROM stg.stg_order_items),
       (SELECT SUM(freight_value) FROM dw.fact_order_items)
UNION ALL
SELECT 'payment_value',
       (SELECT SUM(payment_value) FROM stg.stg_order_payments),
       (SELECT SUM(payment_value) FROM dw.fact_payments);
GO


/* ---------------------------------------------------------------------
   CHECK 3 - Grain uniqueness
   Every duplicate_count should be 0.
   --------------------------------------------------------------------- */
SELECT 'fact_orders by order_id' AS grain_check,
       COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_count
FROM dw.fact_orders
UNION ALL
SELECT 'fact_order_items by order_id + order_item_id',
       COUNT(*) - (SELECT COUNT(*) FROM (SELECT DISTINCT order_id, order_item_id
                                          FROM dw.fact_order_items) x)
FROM dw.fact_order_items
UNION ALL
SELECT 'fact_payments by order_id + payment_sequential',
       COUNT(*) - (SELECT COUNT(*) FROM (SELECT DISTINCT order_id, payment_sequential
                                          FROM dw.fact_payments) x)
FROM dw.fact_payments
UNION ALL
SELECT 'fact_reviews by order_id',
       COUNT(*) - COUNT(DISTINCT order_id)
FROM dw.fact_reviews;
GO


/* ---------------------------------------------------------------------
   CHECK 4 - Customer identity
   Shows why customer_unique_id must be used to count people.
   --------------------------------------------------------------------- */
SELECT
    COUNT(*)                            AS customer_id_rows,
    COUNT(DISTINCT customer_unique_id)  AS real_customers,
    COUNT(*) - COUNT(DISTINCT customer_unique_id) AS overcount_if_wrong_key
FROM dw.dim_customer;
GO


/* ---------------------------------------------------------------------
   CHECK 5 - FAN-OUT DEMONSTRATION
   This is the error the four-fact design prevents.

   The WRONG query joins items to payments on order_id and sums price.
   Because an order with 3 items and 2 payments becomes 6 rows, price
   is counted multiple times and merchandise value is inflated.

   The RIGHT query sums price from order_items alone.
   --------------------------------------------------------------------- */
SELECT
    'WRONG: items joined to payments' AS method,
    SUM(i.price)                       AS merchandise_value
FROM dw.fact_order_items i
JOIN dw.fact_payments    p ON p.order_id = i.order_id

UNION ALL

SELECT
    'RIGHT: items only',
    SUM(price)
FROM dw.fact_order_items;
GO
