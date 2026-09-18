# Source Data Profiling Summary

## Row counts
- customers: 99,441
- geolocation: 1,000,163
- order_items: 112,650
- payments: 103,886
- reviews: 99,224
- orders: 99,441
- products: 32,951
- sellers: 3,095
- category translation: 71

## Key findings

1. Orders and customers both have 99,441 rows.
   This means customer_id is created for each order, so it does not
   identify a real person. customer_unique_id is the real person.

2. order_items has 112,650 rows but there are only 99,441 orders.
   Some orders contain more than one product line.

3. payments has 103,886 rows for 99,441 orders.
   Some orders were paid in more than one transaction.

   Findings 2 and 3 mean these tables cannot be joined into one table,
   or revenue and order counts would be multiplied incorrectly.

4. reviews has 99,224 rows, fewer than orders.
   Not every order received a review.

5. geolocation has 261,831 duplicate rows and must be deduplicated.

6. products has 610 rows with no category name.

7. All date columns are stored as text and must be converted to dates.

8. Missing dates in orders increase along the order lifecycle
   (160 approved, 1,783 carrier, 2,965 delivered).
   These are orders that were never completed, not data errors.
   They should not be filled in.