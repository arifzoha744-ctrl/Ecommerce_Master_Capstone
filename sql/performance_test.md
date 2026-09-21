# SQL Performance Test

## Query tested

Revenue by product category for customers in São Paulo (SP) during Q4 2017.

```sql
SELECT p.category_name_english AS category,
       COUNT(DISTINCT i.order_id) AS orders,
       SUM(i.price) AS merchandise_value
FROM dw.fact_order_items i
JOIN dw.dim_customer c ON c.customer_key = i.customer_key
JOIN dw.dim_product  p ON p.product_key  = i.product_key
WHERE i.purchase_date_key BETWEEN 20171001 AND 20171231
  AND c.[state] = 'SP'
GROUP BY p.category_name_english
ORDER BY merchandise_value DESC;
```

This query was chosen because it reflects a typical dashboard interaction: a
user filtering by a date range and a region, then breaking revenue down by
category. It filters on two columns that had no supporting index.

Full script: `sql/05_performance_test.sql`

---

## Problem identified

Before optimisation, the only indexes on the fact table were the clustered
primary key (`order_item_key`) and the uniqueness constraint on
(`order_id`, `order_item_id`). Neither helps a filter on `purchase_date_key`.

SQL Server therefore had to:

- scan the **entire** `fact_order_items` table (112,650 rows) to find the
  Q4 2017 rows, and
- scan the **entire** `dim_customer` table (99,441 rows) to find customers
  in SP.

Both scans read every page of the table even though only a small fraction of
rows matched the filters.

---

## Change made

Two non-clustered indexes were added:

```sql
CREATE NONCLUSTERED INDEX ix_foi_purchase_date
    ON dw.fact_order_items (purchase_date_key)
    INCLUDE (customer_key, product_key, order_id, price);

CREATE NONCLUSTERED INDEX ix_dim_customer_state
    ON dw.dim_customer ([state]);
```

**Why these columns:**

- `purchase_date_key` is the key column because it is the filter. SQL Server
  can now seek straight to the Q4 2017 range instead of reading the table.
- `customer_key`, `product_key`, `order_id` and `price` are INCLUDED so the
  index covers every column the query needs from the fact table. SQL Server
  never has to go back to the main table to fetch them (no key lookups).
- `state` on `dim_customer` lets the region filter seek directly to SP
  customers.

---

## Results

Measured with `SET STATISTICS IO, TIME ON`.

| Table | Logical reads before | Logical reads after | Reduction |
|---|---:|---:|---:|
| fact_order_items | 1,364 | 163 | 88% |
| dim_customer | 1,538 | 65 | 96% |
| dim_product | 608 | 608 | 0% |
| **Total** | **3,510** | **836** | **76%** |

| Metric | Before | After |
|---|---:|---:|
| CPU time | 125 ms | 78 ms |

---

## Interpretation

**Logical reads is the primary measure.** It counts the number of 8 KB pages
SQL Server had to touch, whether they came from disk or memory, so it is a
fair comparison between runs.

**Elapsed time is not used as the headline figure.** The first run showed an
elapsed time of 38,360 ms, but its statistics also show physical reads and
read-ahead reads, meaning the data was being read from disk into memory for
the first time. The second run found the data already cached. Comparing the
two elapsed times would overstate the benefit of the index, so they are not
reported as the result.

**Why dim_product did not improve:** the query needs the category of every
product that was sold in the filtered period, so SQL Server still reads the
full product dimension to perform the join. No filter is applied to products,
so no index on that table would reduce the pages read.

---

## Trade-offs

Indexes speed up reads but have costs:

- Every insert into `fact_order_items` must now also update the new index,
  so loads are slightly slower.
- The covering index duplicates five columns, using additional storage.

These trade-offs are acceptable here because the warehouse is loaded in bulk
occasionally and queried constantly by dashboards. For a read-heavy
analytical workload, faster queries outweigh slower loads.

---

## Conclusion

Adding two targeted indexes reduced the pages read by 76% overall and by 88%
on the fact table, and cut CPU time from 125 ms to 78 ms. The improvement
comes from replacing full table scans with index seeks on the columns used to
filter.
