/* =====================================================================
   01_create_dimensions.sql
   ---------------------------------------------------------------------
   Builds the dimension tables of the star schema in the dw schema,
   sourced only from the stg staging tables.

   Rebuildable: drops everything first (facts before dimensions, because
   facts hold the foreign keys), so this can be re-run safely.

   Run order:  01_create_dimensions.sql  ->  02_create_facts.sql
               ->  03_validate_model.sql
   ===================================================================== */

USE OlistAnalytics;
GO

SET NOCOUNT ON;
SET DATEFIRST 1;   -- Monday = 1, so weekend logic is predictable
GO

/* ---------------------------------------------------------------------
   Drop existing objects (facts first, then dimensions)
   --------------------------------------------------------------------- */
IF OBJECT_ID('dw.fact_reviews',     'U') IS NOT NULL DROP TABLE dw.fact_reviews;
IF OBJECT_ID('dw.fact_payments',    'U') IS NOT NULL DROP TABLE dw.fact_payments;
IF OBJECT_ID('dw.fact_order_items', 'U') IS NOT NULL DROP TABLE dw.fact_order_items;
IF OBJECT_ID('dw.fact_orders',      'U') IS NOT NULL DROP TABLE dw.fact_orders;

IF OBJECT_ID('dw.dim_product',  'U') IS NOT NULL DROP TABLE dw.dim_product;
IF OBJECT_ID('dw.dim_seller',   'U') IS NOT NULL DROP TABLE dw.dim_seller;
IF OBJECT_ID('dw.dim_customer', 'U') IS NOT NULL DROP TABLE dw.dim_customer;
IF OBJECT_ID('dw.dim_date',     'U') IS NOT NULL DROP TABLE dw.dim_date;
GO


/* =====================================================================
   dim_date
   Grain: one row per calendar day.
   Range covers all purchase, delivery and estimated dates in the data.
   date_key is an integer in YYYYMMDD form.
   ===================================================================== */
CREATE TABLE dw.dim_date (
    date_key       INT          NOT NULL PRIMARY KEY,
    full_date      DATE         NOT NULL UNIQUE,
    [year]         INT          NOT NULL,
    [quarter]      INT          NOT NULL,
    quarter_label  CHAR(2)      NOT NULL,
    [month]        INT          NOT NULL,
    month_name     VARCHAR(10)  NOT NULL,
    month_short    CHAR(3)      NOT NULL,
    year_month     CHAR(7)      NOT NULL,
    day_of_month   INT          NOT NULL,
    day_of_week    INT          NOT NULL,
    day_name       VARCHAR(10)  NOT NULL,
    is_weekend     BIT          NOT NULL
);
GO

;WITH calendar AS (
    SELECT CAST('2016-01-01' AS DATE) AS dt
    UNION ALL
    SELECT DATEADD(DAY, 1, dt) FROM calendar WHERE dt < '2018-12-31'
)
INSERT INTO dw.dim_date
SELECT
    YEAR(dt) * 10000 + MONTH(dt) * 100 + DAY(dt),
    dt,
    YEAR(dt),
    DATEPART(QUARTER, dt),
    'Q' + CAST(DATEPART(QUARTER, dt) AS CHAR(1)),
    MONTH(dt),
    DATENAME(MONTH, dt),
    LEFT(DATENAME(MONTH, dt), 3),
    CONVERT(CHAR(7), dt, 120),
    DAY(dt),
    DATEPART(WEEKDAY, dt),
    DATENAME(WEEKDAY, dt),
    CASE WHEN DATEPART(WEEKDAY, dt) IN (6, 7) THEN 1 ELSE 0 END
FROM calendar
OPTION (MAXRECURSION 0);
GO


/* =====================================================================
   dim_customer
   Grain: one row per customer_id (one per order, as in the source).
   customer_unique_id is carried as an attribute and is the field used
   to count real people.

   Geolocation is joined in here. This is safe ONLY because the Python
   cleaning step collapsed geolocation to one row per zip prefix.
   ===================================================================== */
CREATE TABLE dw.dim_customer (
    customer_key        INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    customer_id         CHAR(32)      NOT NULL UNIQUE,
    customer_unique_id  CHAR(32)      NOT NULL,
    zip_code_prefix     INT           NULL,
    city                NVARCHAR(100) NULL,
    [state]             CHAR(2)       NULL,
    latitude            FLOAT         NULL,
    longitude           FLOAT         NULL
);
GO

INSERT INTO dw.dim_customer
    (customer_id, customer_unique_id, zip_code_prefix, city, [state], latitude, longitude)
SELECT
    c.customer_id,
    c.customer_unique_id,
    c.customer_zip_code_prefix,
    c.customer_city,
    c.customer_state,
    g.geolocation_lat,
    g.geolocation_lng
FROM stg.stg_customers c
LEFT JOIN stg.stg_geolocation g
       ON g.geolocation_zip_code_prefix = c.customer_zip_code_prefix;
GO

CREATE INDEX ix_dim_customer_unique ON dw.dim_customer (customer_unique_id);
GO


/* =====================================================================
   dim_seller
   Grain: one row per seller.
   ===================================================================== */
CREATE TABLE dw.dim_seller (
    seller_key       INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    seller_id        CHAR(32)      NOT NULL UNIQUE,
    zip_code_prefix  INT           NULL,
    city             NVARCHAR(100) NULL,
    [state]          CHAR(2)       NULL,
    latitude         FLOAT         NULL,
    longitude        FLOAT         NULL
);
GO

INSERT INTO dw.dim_seller
    (seller_id, zip_code_prefix, city, [state], latitude, longitude)
SELECT
    s.seller_id,
    s.seller_zip_code_prefix,
    s.seller_city,
    s.seller_state,
    g.geolocation_lat,
    g.geolocation_lng
FROM stg.stg_sellers s
LEFT JOIN stg.stg_geolocation g
       ON g.geolocation_zip_code_prefix = s.seller_zip_code_prefix;
GO


/* =====================================================================
   dim_product
   Grain: one row per product.
   Missing categories were labelled 'unknown' / 'Unknown' in Python.
   ===================================================================== */
CREATE TABLE dw.dim_product (
    product_key            INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    product_id             CHAR(32)      NOT NULL UNIQUE,
    category_name          NVARCHAR(100) NOT NULL,
    category_name_english  NVARCHAR(100) NOT NULL,
    weight_g               FLOAT         NULL,
    length_cm              FLOAT         NULL,
    height_cm              FLOAT         NULL,
    width_cm               FLOAT         NULL,
    photos_qty             FLOAT         NULL
);
GO

INSERT INTO dw.dim_product
    (product_id, category_name, category_name_english,
     weight_g, length_cm, height_cm, width_cm, photos_qty)
SELECT
    product_id,
    product_category_name,
    product_category_name_english,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm,
    product_photos_qty
FROM stg.stg_products;
GO


/* ---------------------------------------------------------------------
   Quick check
   --------------------------------------------------------------------- */
SELECT 'dim_date'     AS table_name, COUNT(*) AS row_count FROM dw.dim_date
UNION ALL SELECT 'dim_customer', COUNT(*) FROM dw.dim_customer
UNION ALL SELECT 'dim_seller',   COUNT(*) FROM dw.dim_seller
UNION ALL SELECT 'dim_product',  COUNT(*) FROM dw.dim_product;
GO
