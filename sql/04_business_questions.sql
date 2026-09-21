/* =====================================================================
   04_business_questions.sql
   ---------------------------------------------------------------------
   Fifteen business questions answered against the dw star schema.

   Every query respects fact-table grain:
     - Merchandise and freight value come ONLY from fact_order_items
     - Payment value comes ONLY from fact_payments
     - Order counts use COUNT(DISTINCT order_id)
     - Customer counts use customer_unique_id
     - Delivery metrics use delivered orders only
     - fact_orders and fact_reviews may be joined on order_id because
       both are at order grain (one row per order), so the join is 1:1

   Techniques covered:
     Joins ................ all questions
     CTEs ................. Q2, Q4, Q5, Q6, Q9, Q12, Q14
     ROW_NUMBER ........... Q6
     RANK / DENSE_RANK .... Q4, Q9
     NTILE ................ Q14
     LAG / LEAD ........... Q1, Q6
     Running totals ....... Q2
     Conditional aggs ..... Q7, Q8, Q12, Q13
     Subqueries ........... Q8, Q9
     Date functions ....... Q6, Q15
     NULL handling ........ Q5, Q7, Q12, Q15
     CASE logic ........... Q5, Q6, Q8

   Run each question on its own: highlight it and press F5.
   ===================================================================== */

USE OlistAnalytics;
GO


/* =====================================================================
   Q1. How is revenue trending month by month, and how fast is it growing?
   ---------------------------------------------------------------------
   Why it matters: the headline growth story for management.
   Technique: LAG to fetch the previous month's value.
   Note: Sep 2016 and the final months of 2018 are partial, so their
   growth percentages are not meaningful.
   ===================================================================== */
WITH monthly AS (
    SELECT
        d.year_month,
        COUNT(DISTINCT i.order_id) AS orders,
        SUM(i.price)               AS merchandise_value
    FROM dw.fact_order_items i
    JOIN dw.dim_date d ON d.date_key = i.purchase_date_key
    GROUP BY d.year_month
)
SELECT
    year_month,
    orders,
    merchandise_value,
    LAG(merchandise_value) OVER (ORDER BY year_month) AS prev_month_value,
    CAST(
        100.0 * (merchandise_value - LAG(merchandise_value) OVER (ORDER BY year_month))
        / NULLIF(LAG(merchandise_value) OVER (ORDER BY year_month), 0)
    AS DECIMAL(8,2)) AS mom_growth_pct
FROM monthly
ORDER BY year_month;

-- Finding:


/* =====================================================================
   Q2. What is the year-to-date revenue at the end of each month?
   ---------------------------------------------------------------------
   Why it matters: shows cumulative progress against the year.
   Technique: running total with SUM() OVER, reset each year.
   ===================================================================== */
WITH monthly AS (
    SELECT
        d.[year],
        d.[month],
        d.year_month,
        SUM(i.price) AS merchandise_value
    FROM dw.fact_order_items i
    JOIN dw.dim_date d ON d.date_key = i.purchase_date_key
    GROUP BY d.[year], d.[month], d.year_month
)
SELECT
    [year],
    year_month,
    merchandise_value,
    SUM(merchandise_value) OVER (
        PARTITION BY [year]
        ORDER BY [month]
        ROWS UNBOUNDED PRECEDING
    ) AS ytd_merchandise_value
FROM monthly
ORDER BY [year], [month];

-- Finding:


/* =====================================================================
   Q3. Which ten product categories generate the most revenue, and what
       share of the total does each contribute?
   ---------------------------------------------------------------------
   Why it matters: shows where the business actually makes its money.
   Technique: window SUM over the whole result for contribution %.
   ===================================================================== */
SELECT TOP 10
    p.category_name_english                 AS category,
    COUNT(DISTINCT i.order_id)              AS orders,
    SUM(i.price)                            AS merchandise_value,
    CAST(100.0 * SUM(i.price) / SUM(SUM(i.price)) OVER ()
         AS DECIMAL(5,2))                   AS contribution_pct
FROM dw.fact_order_items i
JOIN dw.dim_product p ON p.product_key = i.product_key
GROUP BY p.category_name_english
ORDER BY merchandise_value DESC;

-- Finding:


/* =====================================================================
   Q4. Who are the top three sellers by revenue in each state?
   ---------------------------------------------------------------------
   Why it matters: identifies key regional partners to protect.
   Technique: DENSE_RANK partitioned by state.
   ===================================================================== */
WITH seller_revenue AS (
    SELECT
        s.[state],
        s.seller_id,
        COUNT(DISTINCT i.order_id) AS orders,
        SUM(i.price)               AS merchandise_value
    FROM dw.fact_order_items i
    JOIN dw.dim_seller s ON s.seller_key = i.seller_key
    GROUP BY s.[state], s.seller_id
),
ranked AS (
    SELECT
        *,
        DENSE_RANK() OVER (PARTITION BY [state] ORDER BY merchandise_value DESC) AS state_rank
    FROM seller_revenue
)
SELECT [state], state_rank, seller_id, orders, merchandise_value
FROM ranked
WHERE state_rank <= 3
ORDER BY [state], state_rank;

-- Finding:


/* =====================================================================
   Q5. How many customers come back, and how much revenue do they bring?
   ---------------------------------------------------------------------
   Why it matters: retention is usually cheaper than acquisition.
   Technique: CTEs, CASE segmentation, COALESCE for customers whose
   only orders had no items (cancelled / unavailable).
   Customers are counted by customer_unique_id, never customer_id.
   ===================================================================== */
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS order_count
    FROM dw.fact_orders o
    JOIN dw.dim_customer c ON c.customer_key = o.customer_key
    GROUP BY c.customer_unique_id
),
customer_revenue AS (
    SELECT
        c.customer_unique_id,
        SUM(i.price) AS merchandise_value
    FROM dw.fact_order_items i
    JOIN dw.dim_customer c ON c.customer_key = i.customer_key
    GROUP BY c.customer_unique_id
)
SELECT
    CASE WHEN co.order_count > 1 THEN 'Repeat' ELSE 'One-time' END  AS customer_type,
    COUNT(*)                                                         AS customers,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2))   AS pct_of_customers,
    SUM(COALESCE(cr.merchandise_value, 0))                           AS merchandise_value,
    CAST(100.0 * SUM(COALESCE(cr.merchandise_value, 0))
         / SUM(SUM(COALESCE(cr.merchandise_value, 0))) OVER ()
         AS DECIMAL(5,2))                                            AS pct_of_revenue,
    CAST(SUM(COALESCE(cr.merchandise_value, 0)) / COUNT(*)
         AS DECIMAL(10,2))                                           AS revenue_per_customer
FROM customer_orders co
LEFT JOIN customer_revenue cr ON cr.customer_unique_id = co.customer_unique_id
GROUP BY CASE WHEN co.order_count > 1 THEN 'Repeat' ELSE 'One-time' END;

-- Finding:


/* =====================================================================
   Q6. For customers who came back, how long did they wait before
       their second order?
   ---------------------------------------------------------------------
   Why it matters: tells marketing when to time a re-engagement offer.
   Technique: ROW_NUMBER to find the first order, LEAD to find the next,
   DATEDIFF for the gap, CASE for buckets.
   ===================================================================== */
WITH ordered AS (
    SELECT
        c.customer_unique_id,
        o.purchase_timestamp,
        ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id
                           ORDER BY o.purchase_timestamp)      AS order_seq,
        LEAD(o.purchase_timestamp) OVER (PARTITION BY c.customer_unique_id
                                         ORDER BY o.purchase_timestamp) AS next_order_ts
    FROM dw.fact_orders o
    JOIN dw.dim_customer c ON c.customer_key = o.customer_key
),
gaps AS (
    SELECT DATEDIFF(DAY, purchase_timestamp, next_order_ts) AS days_to_second
    FROM ordered
    WHERE order_seq = 1
      AND next_order_ts IS NOT NULL
)
SELECT
    CASE
        WHEN days_to_second = 0    THEN '1. Same day'
        WHEN days_to_second <= 30  THEN '2. 1-30 days'
        WHEN days_to_second <= 90  THEN '3. 31-90 days'
        WHEN days_to_second <= 180 THEN '4. 91-180 days'
        ELSE                            '5. Over 180 days'
    END                                                            AS gap_bucket,
    COUNT(*)                                                       AS customers,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct
FROM gaps
GROUP BY
    CASE
        WHEN days_to_second = 0    THEN '1. Same day'
        WHEN days_to_second <= 30  THEN '2. 1-30 days'
        WHEN days_to_second <= 90  THEN '3. 31-90 days'
        WHEN days_to_second <= 180 THEN '4. 91-180 days'
        ELSE                            '5. Over 180 days'
    END
ORDER BY gap_bucket;

-- Finding:


/* =====================================================================
   Q7. Which customer states suffer the worst delivery, and does it show
       in their review scores?
   ---------------------------------------------------------------------
   Why it matters: points logistics investment at the right regions.
   Technique: conditional aggregation, LEFT JOIN to reviews (orders
   without a review are kept; AVG ignores their NULL score).
   Denominator is delivered orders only.
   ===================================================================== */
SELECT
    c.[state],
    COUNT(*)                                                  AS delivered_orders,
    CAST(AVG(o.delivery_days * 1.0) AS DECIMAL(6,2))          AS avg_delivery_days,
    CAST(100.0 * SUM(CASE WHEN o.is_late = 1 THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,2))                          AS late_pct,
    CAST(AVG(r.review_score * 1.0) AS DECIMAL(4,2))           AS avg_review_score
FROM dw.fact_orders o
JOIN dw.dim_customer    c ON c.customer_key = o.customer_key
LEFT JOIN dw.fact_reviews r ON r.order_id   = o.order_id
WHERE o.delivery_days IS NOT NULL
GROUP BY c.[state]
ORDER BY late_pct DESC;

-- Finding:


/* =====================================================================
   Q8. How much does a late delivery hurt the review score?
   ---------------------------------------------------------------------
   Why it matters: puts a number on the cost of lateness to satisfaction.
   Technique: subquery in FROM, CASE buckets, conditional aggregation.
   ===================================================================== */
SELECT
    delay_bucket,
    COUNT(*)                                                     AS reviewed_orders,
    CAST(AVG(review_score * 1.0) AS DECIMAL(4,2))                AS avg_review_score,
    CAST(100.0 * SUM(CAST(is_negative AS INT)) / COUNT(*)
         AS DECIMAL(5,2))                                        AS negative_review_pct
FROM (
    SELECT
        CASE
            WHEN o.delivery_delay_days <= -10 THEN '1. 10+ days early'
            WHEN o.delivery_delay_days <  0   THEN '2. 1-9 days early'
            WHEN o.delivery_delay_days =  0   THEN '3. On estimated day'
            WHEN o.delivery_delay_days <= 7   THEN '4. 1-7 days late'
            WHEN o.delivery_delay_days <= 14  THEN '5. 8-14 days late'
            ELSE                                   '6. 15+ days late'
        END AS delay_bucket,
        r.review_score,
        r.is_negative
    FROM dw.fact_orders  o
    JOIN dw.fact_reviews r ON r.order_id = o.order_id
    WHERE o.delivery_delay_days IS NOT NULL
) AS delivered_reviews
GROUP BY delay_bucket
ORDER BY delay_bucket;

-- Finding:


/* =====================================================================
   Q9. Which categories bring in above-average revenue but earn
       below-average review scores?
   ---------------------------------------------------------------------
   Why it matters: these categories are valuable but at risk.
   Technique: CTEs, RANK, subqueries for the two averages.
   Grain note: an order can contain several categories, so each review
   is attributed once to each DISTINCT (order, category) pair.
   ===================================================================== */
WITH category_revenue AS (
    SELECT
        p.category_name_english AS category,
        SUM(i.price)            AS merchandise_value,
        RANK() OVER (ORDER BY SUM(i.price) DESC) AS revenue_rank
    FROM dw.fact_order_items i
    JOIN dw.dim_product p ON p.product_key = i.product_key
    GROUP BY p.category_name_english
),
order_category AS (
    SELECT DISTINCT i.order_id, p.category_name_english AS category
    FROM dw.fact_order_items i
    JOIN dw.dim_product p ON p.product_key = i.product_key
),
category_score AS (
    SELECT
        oc.category,
        COUNT(*)                      AS reviewed_orders,
        AVG(r.review_score * 1.0)     AS avg_review_score
    FROM order_category oc
    JOIN dw.fact_reviews r ON r.order_id = oc.order_id
    GROUP BY oc.category
)
SELECT
    cr.revenue_rank,
    cr.category,
    cr.merchandise_value,
    cs.reviewed_orders,
    CAST(cs.avg_review_score AS DECIMAL(4,2)) AS avg_review_score
FROM category_revenue cr
JOIN category_score   cs ON cs.category = cr.category
WHERE cr.merchandise_value > (SELECT AVG(merchandise_value) FROM category_revenue)
  AND cs.avg_review_score  < (SELECT AVG(review_score * 1.0) FROM dw.fact_reviews)
ORDER BY cr.revenue_rank;

-- Finding:


/* =====================================================================
   Q10. In which categories is shipping cost heaviest relative to the
        price of the goods?
   ---------------------------------------------------------------------
   Why it matters: high freight % suppresses conversion and margin.
   Technique: aggregate ratio, HAVING to exclude tiny categories.
   ===================================================================== */
SELECT TOP 15
    p.category_name_english                            AS category,
    COUNT(*)                                           AS items_sold,
    CAST(AVG(i.price)         AS DECIMAL(10,2))        AS avg_price,
    CAST(AVG(i.freight_value) AS DECIMAL(10,2))        AS avg_freight,
    CAST(100.0 * SUM(i.freight_value) / NULLIF(SUM(i.price), 0)
         AS DECIMAL(6,2))                              AS freight_pct
FROM dw.fact_order_items i
JOIN dw.dim_product p ON p.product_key = i.product_key
GROUP BY p.category_name_english
HAVING COUNT(*) >= 100
ORDER BY freight_pct DESC;

-- Finding:


/* =====================================================================
   Q11. How do customers pay, and does payment method affect spend?
   ---------------------------------------------------------------------
   Why it matters: informs payment partnerships and installment offers.
   Technique: aggregation at payment grain. Uses payment_value, NOT
   price, because this question is about money actually transferred.
   ===================================================================== */
SELECT
    payment_type,
    COUNT(DISTINCT order_id)                                   AS orders,
    COUNT(*)                                                   AS transactions,
    SUM(payment_value)                                         AS payment_value,
    CAST(100.0 * SUM(payment_value) / SUM(SUM(payment_value)) OVER ()
         AS DECIMAL(5,2))                                      AS pct_of_payment_value,
    CAST(AVG(payment_value) AS DECIMAL(10,2))                  AS avg_transaction_value,
    CAST(AVG(payment_installments * 1.0) AS DECIMAL(5,2))      AS avg_installments
FROM dw.fact_payments
GROUP BY payment_type
ORDER BY payment_value DESC;

-- Finding:


/* =====================================================================
   Q12. Which established sellers (30+ orders) have the worst delivery
        record, and how does that affect their ratings?
   ---------------------------------------------------------------------
   Why it matters: a seller-management watch list.
   Technique: CTEs, conditional aggregation, NULLIF to avoid divide by
   zero, LEFT JOIN so unreviewed orders are not lost.
   Grain note: a seller is counted once per order even if they sold
   several items in it, via SELECT DISTINCT.
   ===================================================================== */
WITH seller_orders AS (
    SELECT DISTINCT seller_key, order_id
    FROM dw.fact_order_items
),
seller_revenue AS (
    SELECT seller_key, SUM(price) AS merchandise_value
    FROM dw.fact_order_items
    GROUP BY seller_key
),
seller_performance AS (
    SELECT
        so.seller_key,
        COUNT(*)                                             AS orders,
        SUM(CASE WHEN o.is_late = 1          THEN 1 ELSE 0 END) AS late_orders,
        SUM(CASE WHEN o.is_late IS NOT NULL  THEN 1 ELSE 0 END) AS delivered_orders,
        AVG(r.review_score * 1.0)                            AS avg_review_score
    FROM seller_orders so
    JOIN dw.fact_orders       o ON o.order_id = so.order_id
    LEFT JOIN dw.fact_reviews r ON r.order_id = so.order_id
    GROUP BY so.seller_key
)
SELECT TOP 20
    s.seller_id,
    s.[state],
    sp.orders,
    sr.merchandise_value,
    CAST(100.0 * sp.late_orders / NULLIF(sp.delivered_orders, 0)
         AS DECIMAL(5,2))                          AS late_pct,
    CAST(sp.avg_review_score AS DECIMAL(4,2))      AS avg_review_score
FROM seller_performance sp
JOIN seller_revenue sr ON sr.seller_key = sp.seller_key
JOIN dw.dim_seller  s  ON s.seller_key  = sp.seller_key
WHERE sp.orders >= 30
ORDER BY late_pct DESC;

-- Finding:


/* =====================================================================
   Q13. How has the cancellation rate moved over time?
   ---------------------------------------------------------------------
   Why it matters: rising cancellations signal stock or trust problems.
   Technique: conditional aggregation by month.
   ===================================================================== */
SELECT
    d.year_month,
    COUNT(*)                                                         AS orders,
    SUM(CAST(o.is_cancelled AS INT))                                 AS cancelled,
    SUM(CASE WHEN o.order_status = 'unavailable' THEN 1 ELSE 0 END)  AS unavailable,
    CAST(100.0 * SUM(CAST(o.is_cancelled AS INT)) / COUNT(*)
         AS DECIMAL(5,2))                                            AS cancellation_pct
FROM dw.fact_orders o
JOIN dw.dim_date d ON d.date_key = o.purchase_date_key
GROUP BY d.year_month
ORDER BY d.year_month;

-- Finding:


/* =====================================================================
   Q14. How concentrated is revenue across the customer base?
   ---------------------------------------------------------------------
   Why it matters: shows how dependent the business is on top spenders.
   Technique: NTILE(4) to split customers into spend quartiles.
   ===================================================================== */
WITH customer_spend AS (
    SELECT
        c.customer_unique_id,
        SUM(i.price) AS total_spend
    FROM dw.fact_order_items i
    JOIN dw.dim_customer c ON c.customer_key = i.customer_key
    GROUP BY c.customer_unique_id
),
quartiled AS (
    SELECT
        *,
        NTILE(4) OVER (ORDER BY total_spend DESC) AS spend_quartile
    FROM customer_spend
)
SELECT
    spend_quartile,
    COUNT(*)                                                   AS customers,
    CAST(MIN(total_spend) AS DECIMAL(10,2))                    AS min_spend,
    CAST(MAX(total_spend) AS DECIMAL(10,2))                    AS max_spend,
    CAST(AVG(total_spend) AS DECIMAL(10,2))                    AS avg_spend,
    CAST(100.0 * SUM(total_spend) / SUM(SUM(total_spend)) OVER ()
         AS DECIMAL(5,2))                                      AS pct_of_revenue
FROM quartiled
GROUP BY spend_quartile
ORDER BY spend_quartile;

-- Finding:


/* =====================================================================
   Q15. How accurate are the delivery estimates given to customers?
   ---------------------------------------------------------------------
   Why it matters: over-padded estimates may lose sales at checkout;
   under-padded ones cause late deliveries and bad reviews.
   Technique: date arithmetic on derived day counts, NULL filtering
   (only delivered orders have an actual delivery time).
   ===================================================================== */
SELECT
    c.[state],
    COUNT(*)                                                    AS delivered_orders,
    CAST(AVG(o.estimated_days * 1.0) AS DECIMAL(6,2))           AS avg_promised_days,
    CAST(AVG(o.delivery_days  * 1.0) AS DECIMAL(6,2))           AS avg_actual_days,
    CAST(AVG((o.estimated_days - o.delivery_days) * 1.0)
         AS DECIMAL(6,2))                                       AS avg_buffer_days,
    CAST(100.0 * SUM(CASE WHEN o.delivery_delay_days <= -10 THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,2))                            AS pct_10plus_days_early
FROM dw.fact_orders o
JOIN dw.dim_customer c ON c.customer_key = o.customer_key
WHERE o.delivery_days  IS NOT NULL
  AND o.estimated_days IS NOT NULL
GROUP BY c.[state]
HAVING COUNT(*) >= 500
ORDER BY avg_buffer_days DESC;

-- Finding:
