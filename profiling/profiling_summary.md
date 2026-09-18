# Source Data Profiling Summary

## Row counts

| Dataset | Rows |
|---|---|
| customers | 99,441 |
| geolocation | 1,000,163 |
| order_items | 112,650 |
| payments | 103,886 |
| reviews | 99,224 |
| orders | 99,441 |
| products | 32,951 |
| sellers | 3,095 |
| category translation | 71 |

## Data quality observations

1. Orders and customers both have 99,441 rows. This means customer_id is
   created for each order, so it does not identify a real person.
   customer_unique_id is the real person.

2. order_items has 112,650 rows but there are only 99,441 orders.
   Some orders contain more than one product line.

3. payments has 103,886 rows for 99,441 orders. Some orders were paid
   in more than one transaction.

   Findings 2 and 3 mean these tables cannot be joined into one flat
   table, or revenue and order counts would be multiplied incorrectly.

4. reviews has 99,224 rows, fewer than orders. Not every order was reviewed.

5. geolocation has 261,831 duplicate rows and must be deduplicated.

6. products has 610 rows with no category name.

7. All date columns are stored as text and must be converted to dates.

8. Missing dates in orders increase along the order lifecycle
   (160 approved, 1,783 carrier handover, 2,965 delivered).
   These are orders that were never completed, not data errors.
   They should not be filled in.

## Key and relationship findings

- All primary keys are unique except reviews. review_id repeats and some
  orders have more than one review, so reviews are not one per order.
  A rule is needed before joining (keep latest review per order).

- 99,441 customer_id values map to only 96,096 customer_unique_id values.
  This confirms customer_unique_id is the real person and must be used
  for all customer counting and repeat customer analysis.

- No orphan records. Every foreign key resolves correctly:
  items to orders, payments to orders, reviews to orders,
  items to products, items to sellers, orders to customers.

- Coverage gaps: 775 orders have no items, 768 have no review,
  1 has no payment. These are mainly cancelled or unavailable orders.

- Order status distribution: delivered 96,478, shipped 1,107,
  cancelled 625, unavailable 609, invoiced 314, processing 301,
  created 5, approved 2.
  Completed Order will be defined as status = 'delivered'.

- Data covers 2016-09-04 to 2018-10-17. The first and last months are
  partial and will distort trend charts unless handled.