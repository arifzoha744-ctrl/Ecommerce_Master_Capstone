/* =====================================================================
   02_create_facts.sql
   ---------------------------------------------------------------------
   Builds the four fact tables. Each fact table sits at its OWN grain.
   They are never joined to each other - they connect only through the
   shared dimensions. This is what prevents revenue fan-out.

     fact_orders       one row per order
     fact_order_items  one row per item line within an order
     fact_payments     one row per payment transaction
     fact_reviews      one row per reviewed order

   Every fact carries customer_key and purchase_date_key so that all
   four can be filtered by the same customer and date slicers in
   Power BI without joining fact to fact.

   Run AFTER 01_create_dimensions.sql.
   ===================================================================== */

USE OlistAnalytics;
GO

SET NOCOUNT ON;
GO


/* =====================================================================
   fact_orders
   Grain: one row per order.
   Holds order status and all delivery timing measures.
   ===================================================================== */
CREATE TABLE dw.fact_orders (
    order_key            INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    order_id             CHAR(32)    NOT NULL UNIQUE,
    customer_key         INT         NOT NULL REFERENCES dw.dim_customer (customer_key),
    purchase_date_key    INT         NOT NULL REFERENCES dw.dim_date (date_key),
    delivered_date_key   INT         NULL     REFERENCES dw.dim_date (date_key),
    estimated_date_key   INT         NULL     REFERENCES dw.dim_date (date_key),
    order_status         VARCHAR(20) NOT NULL,
    purchase_timestamp   DATETIME2   NOT NULL,
    delivery_days        INT         NULL,
    estimated_days       INT         NULL,
    delivery_delay_days  INT         NULL,
    is_delivered         BIT         NOT NULL,
    is_cancelled         BIT         NOT NULL,
    is_late              BIT         NULL      -- NULL when never delivered
);
GO

INSERT INTO dw.fact_orders
    (order_id, customer_key, purchase_date_key, delivered_date_key, estimated_date_key,
     order_status, purchase_timestamp, delivery_days, estimated_days,
     delivery_delay_days, is_delivered, is_cancelled, is_late)
SELECT
    o.order_id,
    dc.customer_key,
    CAST(CONVERT(CHAR(8), o.order_purchase_timestamp,      112) AS INT),
    CAST(CONVERT(CHAR(8), o.order_delivered_customer_date, 112) AS INT),
    CAST(CONVERT(CHAR(8), o.order_estimated_delivery_date, 112) AS INT),
    o.order_status,
    o.order_purchase_timestamp,
    o.delivery_days,
    o.estimated_days,
    o.delivery_delay_days,
    o.is_delivered,
    o.is_cancelled,
    o.is_late
FROM stg.stg_orders o
JOIN dw.dim_customer dc ON dc.customer_id = o.customer_id;
GO


/* =====================================================================
   fact_order_items
   Grain: one row per item line within an order.
   Home of merchandise value (price) and freight value.
   ===================================================================== */
CREATE TABLE dw.fact_order_items (
    order_item_key     INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    order_id           CHAR(32)      NOT NULL,
    order_item_id      INT           NOT NULL,
    customer_key       INT           NOT NULL REFERENCES dw.dim_customer (customer_key),
    product_key        INT           NOT NULL REFERENCES dw.dim_product  (product_key),
    seller_key         INT           NOT NULL REFERENCES dw.dim_seller   (seller_key),
    purchase_date_key  INT           NOT NULL REFERENCES dw.dim_date     (date_key),
    order_status       VARCHAR(20)   NOT NULL,
    price              DECIMAL(12,2) NOT NULL,
    freight_value      DECIMAL(12,2) NOT NULL,
    CONSTRAINT uq_fact_order_items UNIQUE (order_id, order_item_id)
);
GO

INSERT INTO dw.fact_order_items
    (order_id, order_item_id, customer_key, product_key, seller_key,
     purchase_date_key, order_status, price, freight_value)
SELECT
    i.order_id,
    i.order_item_id,
    dc.customer_key,
    dp.product_key,
    ds.seller_key,
    CAST(CONVERT(CHAR(8), o.order_purchase_timestamp, 112) AS INT),
    o.order_status,
    i.price,
    i.freight_value
FROM stg.stg_order_items i
JOIN stg.stg_orders     o  ON o.order_id     = i.order_id
JOIN dw.dim_customer    dc ON dc.customer_id = o.customer_id
JOIN dw.dim_product     dp ON dp.product_id  = i.product_id
JOIN dw.dim_seller      ds ON ds.seller_id   = i.seller_id;
GO


/* =====================================================================
   fact_payments
   Grain: one row per payment transaction.
   Home of payment_value. Never summed together with price.
   ===================================================================== */
CREATE TABLE dw.fact_payments (
    payment_key           INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    order_id              CHAR(32)      NOT NULL,
    payment_sequential    INT           NOT NULL,
    customer_key          INT           NOT NULL REFERENCES dw.dim_customer (customer_key),
    purchase_date_key     INT           NOT NULL REFERENCES dw.dim_date     (date_key),
    order_status          VARCHAR(20)   NOT NULL,
    payment_type          VARCHAR(30)   NOT NULL,
    payment_installments  INT           NOT NULL,
    payment_value         DECIMAL(12,2) NOT NULL,
    CONSTRAINT uq_fact_payments UNIQUE (order_id, payment_sequential)
);
GO

INSERT INTO dw.fact_payments
    (order_id, payment_sequential, customer_key, purchase_date_key,
     order_status, payment_type, payment_installments, payment_value)
SELECT
    p.order_id,
    p.payment_sequential,
    dc.customer_key,
    CAST(CONVERT(CHAR(8), o.order_purchase_timestamp, 112) AS INT),
    o.order_status,
    p.payment_type,
    p.payment_installments,
    p.payment_value
FROM stg.stg_order_payments p
JOIN stg.stg_orders  o  ON o.order_id     = p.order_id
JOIN dw.dim_customer dc ON dc.customer_id = o.customer_id;
GO


/* =====================================================================
   fact_reviews
   Grain: one row per reviewed order (latest review kept in Python).
   ===================================================================== */
CREATE TABLE dw.fact_reviews (
    review_key         INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    review_id          CHAR(32)  NOT NULL,
    order_id           CHAR(32)  NOT NULL UNIQUE,
    customer_key       INT       NOT NULL REFERENCES dw.dim_customer (customer_key),
    purchase_date_key  INT       NOT NULL REFERENCES dw.dim_date     (date_key),
    review_date_key    INT       NULL     REFERENCES dw.dim_date     (date_key),
    review_score       INT       NOT NULL,
    has_comment        BIT       NOT NULL,
    is_negative        BIT       NOT NULL,   -- score 1 or 2
    is_positive        BIT       NOT NULL    -- score 4 or 5
);
GO

INSERT INTO dw.fact_reviews
    (review_id, order_id, customer_key, purchase_date_key, review_date_key,
     review_score, has_comment, is_negative, is_positive)
SELECT
    r.review_id,
    r.order_id,
    dc.customer_key,
    CAST(CONVERT(CHAR(8), o.order_purchase_timestamp, 112) AS INT),
    CAST(CONVERT(CHAR(8), r.review_creation_date,     112) AS INT),
    r.review_score,
    CASE WHEN r.review_comment_message IS NOT NULL THEN 1 ELSE 0 END,
    CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END,
    CASE WHEN r.review_score >= 4 THEN 1 ELSE 0 END
FROM stg.stg_order_reviews r
JOIN stg.stg_orders  o  ON o.order_id     = r.order_id
JOIN dw.dim_customer dc ON dc.customer_id = o.customer_id;
GO


/* ---------------------------------------------------------------------
   Note on indexes:
   Only primary keys and uniqueness constraints are created here.
   Foreign-key indexes are deliberately left for the SQL performance
   step, so that their effect can be measured before and after.
   --------------------------------------------------------------------- */


/* ---------------------------------------------------------------------
   Quick check
   --------------------------------------------------------------------- */
SELECT 'fact_orders'      AS table_name, COUNT(*) AS row_count FROM dw.fact_orders
UNION ALL SELECT 'fact_order_items', COUNT(*) FROM dw.fact_order_items
UNION ALL SELECT 'fact_payments',    COUNT(*) FROM dw.fact_payments
UNION ALL SELECT 'fact_reviews',     COUNT(*) FROM dw.fact_reviews;
GO
