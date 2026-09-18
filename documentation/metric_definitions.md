# Business Metric Definitions

Every metric used in SQL and Power BI is defined here first. Any measure that
appears on a dashboard must trace back to one of these definitions.

---

## Why this document exists

The dataset contains three different money columns that are easy to confuse:

| Column | Source table | What it actually is |
|---|---|---|
| `price` | order_items | The value of the goods, excluding shipping |
| `freight_value` | order_items | The shipping cost charged for that item |
| `payment_value` | order_payments | What the customer actually transferred, including freight and installment effects |

These are **not** interchangeable and are never added together. Each one is
summed only from its own table, at its own grain.

---

## Order metrics

| Metric | Definition | Source |
|---|---|---|
| **Order** | One row in the orders table, identified by `order_id`. | orders |
| **Completed Order** | An order where `order_status = 'delivered'`. 96,478 orders. | orders |
| **Cancelled Order** | An order where `order_status = 'canceled'`. 625 orders. | orders |
| **In-Progress Order** | Any order not delivered and not cancelled: shipped, invoiced, processing, approved, created, unavailable. 2,338 orders. | orders |
| **Total Orders** | Distinct count of `order_id`. | orders |

Note: `unavailable` is treated as in-progress rather than cancelled, because
the status is distinct in the source and the business may treat it differently.
This choice is stated so it can be changed if management disagrees.

---

## Customer metrics

| Metric | Definition | Source |
|---|---|---|
| **Order-level customer** | `customer_id`. Generated per order. Used only to join orders to the customer table. Never counted. | customers |
| **Customer** | Distinct count of `customer_unique_id`. 96,096 customers. | customers |
| **Repeat Customer** | A `customer_unique_id` appearing on more than one distinct `order_id`. | orders + customers |
| **New Customer** | A `customer_unique_id` whose first order falls in the period being viewed. | orders + customers |
| **Repeat Customer %** | Repeat customers divided by total customers. | derived |

---

## Financial metrics

| Metric | Definition | Source | Grain |
|---|---|---|---|
| **Merchandise Value** | `SUM(price)`. The value of goods sold, excluding shipping. This is the project's primary revenue measure. | order_items | item |
| **Freight Value** | `SUM(freight_value)`. Shipping cost charged to customers. | order_items | item |
| **Payment Value** | `SUM(payment_value)`. What customers actually paid. Includes freight. | order_payments | payment transaction |
| **Average Order Value** | Merchandise Value divided by Total Orders. | derived | — |
| **Freight %** | Freight Value divided by Merchandise Value. Measures shipping burden. | derived | — |
| **Contribution %** | A segment's Merchandise Value divided by total Merchandise Value. | derived | — |

Merchandise Value is used as the headline revenue figure rather than Payment
Value, because it isolates the value of goods sold from shipping cost and from
payment mechanics such as installments. Payment Value is reported separately in
the payment analysis.

---

## Delivery metrics

All delivery metrics are calculated only for orders that were actually
delivered. Undelivered orders are excluded rather than counted as late.

| Metric | Definition |
|---|---|
| **Delivery Days** | `order_delivered_customer_date` minus `order_purchase_timestamp`, in days. |
| **Estimated Days** | `order_estimated_delivery_date` minus `order_purchase_timestamp`, in days. |
| **Delivery Delay** | `order_delivered_customer_date` minus `order_estimated_delivery_date`, in days. Positive means late, negative means early. |
| **On-Time Delivery** | A delivered order where Delivery Delay is 0 or negative. |
| **Late Delivery** | A delivered order where Delivery Delay is greater than 0. |
| **On-Time Delivery %** | On-time deliveries divided by delivered orders. |
| **Late Delivery %** | Late deliveries divided by delivered orders. |
| **Average Delivery Delay** | Average Delivery Delay across delivered orders only. |

The denominator for all delivery percentages is **delivered orders**, not total
orders. Using total orders would understate on-time performance, because orders
still in transit would count against it.

---

## Satisfaction metrics

| Metric | Definition | Source |
|---|---|---|
| **Review Score** | The 1 to 5 rating given by the customer. | order_reviews |
| **Average Review Score** | Mean review score across reviewed orders. | order_reviews |
| **Reviewed Orders** | Orders with at least one review. 98,673 of 99,441. | order_reviews |
| **Negative Review** | A review scored 1 or 2. |  order_reviews |
| **Positive Review** | A review scored 4 or 5. | order_reviews |

Average Review Score is calculated over reviewed orders only. Orders with no
review are excluded rather than treated as neutral, because a missing review is
not a score.

---

## Time intelligence metrics

| Metric | Definition |
|---|---|
| **Previous Month Value** | The same measure shifted back one month using the date dimension. |
| **Previous Year Value** | The same measure shifted back one year. |
| **Month-over-Month Growth %** | (Current minus Previous Month) divided by Previous Month. |
| **Year-over-Year Growth %** | (Current minus Previous Year) divided by Previous Year. |

The dataset covers 2016-09-04 to 2018-10-17. The first and last months are
partial and will show artificially low values in any trend chart. Growth
percentages for those two months are not reliable and are excluded from
conclusions.

---

## Rules that apply everywhere

1. A measure is only ever summed from the table it belongs to.
2. `price`, `freight_value` and `payment_value` are never added together.
3. Customer counts always use `customer_unique_id`, never `customer_id`.
4. Delivery percentages always use delivered orders as the denominator.
5. Review averages always exclude orders with no review.
6. Order counts always use distinct `order_id`, never a row count of a joined
   table.
