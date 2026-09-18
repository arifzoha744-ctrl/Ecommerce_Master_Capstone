# Data Quality Report

The five most significant data-quality issues found during profiling, with the
action taken and the reasoning behind it.

---

## 1. Geolocation is many-to-many and heavily duplicated

**Issue:** 1,000,163 rows containing 261,831 exact duplicates, with many
coordinate rows per zip code prefix.

**Affected records:** 981,148 rows removed (98% of the table).

**Business impact:** Joining geolocation to customers or sellers on zip prefix
would multiply every customer and seller row, inflating customer counts,
revenue by state, and every geographic KPI on the dashboard.

**Action:** Correct — deduplicated, then aggregated to one row per zip prefix
using the mean latitude and longitude and the most frequent city and state.

**Reason:** A geographic dimension must have a unique key. The mean coordinate
is accurate enough for the city and state level at which the dashboard reports.
Dropping the table entirely would remove all mapping capability.

---

## 2. Reviews are not one per order

**Issue:** review_id is not unique, and 551 orders carry more than one review.

**Affected records:** 551 rows removed (99,224 reduced to 98,673).

**Business impact:** Joining reviews to orders would duplicate order rows,
inflating order counts and any revenue measure filtered by review score.
Average review score would also be weighted incorrectly toward orders that
happened to be reviewed twice.

**Action:** Correct — kept one review per order, the most recent by
review_creation_date.

**Reason:** The latest review represents the customer's final assessment.
Averaging the scores was considered but rejected, because it produces scores
that no customer actually gave and is harder to explain to management.

---

## 3. Products with missing category names

**Issue:** 610 products have no product_category_name. A further 13 have a
category with no matching entry in the translation file, giving 623 products
with no usable English category.

**Affected records:** 623 products — labelled, but retained.

**Business impact:** These products generated real sales. Excluding them would
silently remove revenue from category analysis and cause merchandise value
totals to disagree between the product dashboard and the executive page.

**Action:** Flag — assigned the category "unknown" and the English label
"Unknown" rather than excluding the rows.

**Reason:** Preserving revenue integrity matters more than having a tidy
category list. Showing "Unknown" as a visible category also makes the gap
honest rather than hiding it.

---

## 4. Missing dates across the order lifecycle

**Issue:** 160 orders have no approval date, 1,783 have no carrier handover
date, and 2,965 have no customer delivery date.

**Affected records:** 2,965 orders — retained unchanged.

**Business impact:** If these were treated as errors and filled or removed,
delivery performance would be overstated, because orders that were never
delivered would either disappear from the denominator or appear to have been
delivered successfully.

**Action:** Retain — left as null.

**Reason:** The null counts increase along the lifecycle (160, then 1,783, then
2,965), which matches the order status distribution. They record orders that
never reached that stage. This is meaningful information, not missing data.
On-time and late flags are therefore left null for undelivered orders rather
than defaulted to false.

---

## 5. Two customer identifiers with different meanings

**Issue:** The customers table contains both customer_id and
customer_unique_id. There are 99,441 customer_id values but only 96,096
customer_unique_id values.

**Affected records:** All 99,441 rows.

**Business impact:** Using customer_id to count customers would report 99,441
customers instead of 96,096, overstating the customer base by 3.5% and making
repeat-customer analysis impossible, since every repeat purchase would appear
to come from a new person.

**Action:** Correct — customer_id is used only to join orders to customers.
customer_unique_id is used for all customer counting, segmentation and repeat
purchase analysis.

**Reason:** customer_id is generated per order and does not identify a person.
customer_unique_id identifies the actual individual across multiple orders.

---

## Issues considered and deliberately not actioned

| Observation | Records | Decision | Reason |
|---|---|---|---|
| Missing review comment titles | 87,656 | Retain | Means no text was written, not missing data |
| Missing review comment messages | 58,247 | Retain | Same as above |
| Orders with no order items | 775 | Retain | Mainly cancelled or unavailable orders |
| Orders with no review | 768 | Retain | Reviewing is optional for the customer |
| Payments with 0 installments | 2 | Correct to 1 | A single payment is one installment |
| Payments typed 'not_defined' | 3 | Retain and flag | Too few to affect results; removing would break order payment totals |
| Products with missing dimensions | 2 | Retain | Dimensions are not used in any reported measure |
| Misspelled source column names | 2 columns | Correct | "lenght" renamed to "length" for readability; no data changed |

---

## Summary of data integrity

All foreign key relationships were verified during profiling and contain no
orphan records. Every order item, payment and review resolves to a real order,
every item resolves to a real product and seller, and every order resolves to a
real customer. No referential integrity repairs were required.
