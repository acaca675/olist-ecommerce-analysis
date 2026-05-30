# Tableau + PostgreSQL Connection Guide
## Olist E-Commerce Analysis Project

---

## Step 1: Install PostgreSQL ODBC Driver (if needed)
Tableau connects to PostgreSQL natively — no extra driver needed on most systems.
If you see a driver error, download from: https://www.postgresql.org/ftp/odbc/versions/

---

## Step 2: Create the Tableau Views (REQUIRED before connecting)

In SQL Workbench or pgAdmin, run the views script first:
```
sql/views/04_tableau_views.sql
```

This creates 4 optimised views in the `olist` schema:
- `v_orders_full`          — master order view with all metrics
- `v_seller_metrics`       — aggregated seller KPIs
- `v_category_performance` — category revenue + satisfaction
- `v_geo_orders`           — state-level metrics with lat/lng

**Why views?** Tableau's drag-and-drop creates inefficient SQL.
Pre-joining in views means Tableau gets clean, fast data.

---

## Step 3: Connect Tableau to PostgreSQL

1. Open Tableau Desktop
2. Click **Connect → To a Server → PostgreSQL**
3. Enter connection details:
   - Server:   `localhost`
   - Port:     `5432`
   - Database: `olist_db`
   - Username: `postgres`
   - Password: *(your password)*
4. Click **Sign In**
5. In the left panel, set **Schema = olist**
6. Drag these views to the canvas:
   - `v_orders_full`
   - `v_seller_metrics`
   - `v_category_performance`
   - `v_geo_orders`

---

## Step 4: Dashboard 1 — Executive Summary

### KPI Strip (top row — use text marks)
| KPI | Field | Format |
|-----|-------|--------|
| Total GMV | SUM([Total Payment]) | Currency R$ |
| Total Orders | COUNTD([Order Id]) | Number |
| Avg Review Score | AVG([Review Score]) | Decimal (1dp) |
| On-Time Rate | formula below | Percentage |

**On-Time Rate calculated field:**
```
SUM(IF [Delivery Status] = "On Time" THEN 1 ELSE 0 END)
/ COUNT([Order Id])
```

### Monthly GMV Line Chart
- Rows: SUM([Total Payment])
- Columns: [Order Month] (continuous)
- Mark type: Line
- Add reference line at average

### Brazil Map
- Data source: `v_geo_orders`
- Mark type: Map
- Latitude: AVG([State Lat])
- Longitude: AVG([State Lng])
- Color: SUM([Total Gmv])
- Size: SUM([Total Orders])
- Color palette: Sequential (orange)

### Top 10 Categories Bar
- Data source: `v_category_performance`
- Rows: [Category English] (sorted by SUM(Gross Revenue) desc)
- Columns: SUM([Gross Revenue])
- Filter: TOP 10 by SUM(Gross Revenue)
- Color: single colour (match dashboard accent)

---

## Step 5: Dashboard 2 — Delivery Performance

### On-Time Rate by State (horizontal bar)
- Data source: `v_orders_full` filtered to delivered orders
- Calculated field: on-time rate (as above)
- Rows: [Customer State]
- Columns: On-Time Rate %
- Color: diverging (red = low, green = high) with midpoint at 90%
- Sort: ascending (worst states at top)

### Delay Heatmap (seller state → customer state)
- Create a new custom SQL connection:
```sql
SELECT
    s.seller_state,
    c.customer_state,
    ROUND(AVG(EXTRACT(EPOCH FROM (
        o.order_delivered_customer_date - o.order_estimated_delivery_date
    )) / 86400.0)::NUMERIC, 1) AS avg_delay_days
FROM olist.olist_orders o
JOIN olist.olist_customers c ON o.customer_id = c.customer_id
JOIN olist.olist_order_items oi ON o.order_id = oi.order_id
JOIN olist.olist_sellers s ON oi.seller_id = s.seller_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY s.seller_state, c.customer_state
```
- Rows: [Seller State], Columns: [Customer State]
- Color: SUM([Avg Delay Days])
- Mark type: Square

---

## Step 6: Dashboard 3 — Customer Satisfaction

### Review Score Distribution (histogram)
- Data source: `v_orders_full`
- Columns: [Review Score] (as dimension)
- Rows: COUNT([Order Id])
- Mark type: Bar
- Color: conditional (1=red, 5=green, others=grey)

### Delivery Delay vs Review Score (scatter)
- Rows: AVG([Review Score])
- Columns: AVG([Delay Days])
- Detail: [Customer State]
- Add trend line (linear)
- This visualises the core finding: delay → poor reviews

### Score by Category (bar — sorted)
- Data source: `v_category_performance`
- Rows: [Category English]
- Columns: AVG([Avg Review Score])
- Filter: categories with >500 orders (reduce noise)
- Color encode: lowest scores = red, highest = teal
- Sort: ascending (worst quality at top — tells the story)

---

## Step 7: Dashboard 4 — Seller Intelligence

### Revenue vs Quality Quadrant (scatter)
- Data source: `v_seller_metrics`
- Columns: SUM([Gross Revenue])
- Rows: AVG([Avg Review Score])
- Detail: [Seller Id]
- Add reference lines: AVG(Gross Revenue) and AVG(Review Score)
- This creates 4 visible quadrants
- Colour by segment (use a calculated field):
```
IF SUM([Gross Revenue]) > WINDOW_AVG(SUM([Gross Revenue]))
   AND AVG([Avg Review Score]) >= WINDOW_AVG(AVG([Avg Review Score]))
   THEN "Champion"
ELSEIF SUM([Gross Revenue]) > WINDOW_AVG(SUM([Gross Revenue]))
   THEN "High Revenue, Low Quality"
ELSEIF AVG([Avg Review Score]) >= WINDOW_AVG(AVG([Avg Review Score]))
   THEN "Rising Star"
ELSE "At Risk"
END
```

### Top 20 Sellers Table
- Data source: `v_seller_metrics`
- Rows: [Seller Id], [Seller State], SUM(Gross Revenue), AVG(Avg Review Score), AVG(Avg Fulfillment Days)
- Sort by SUM(Gross Revenue) desc
- Add conditional formatting bars on Gross Revenue column

---

## Step 8: Publish to Tableau Public

1. In Tableau Desktop: **Server → Tableau Public → Save to Tableau Public**
2. Sign in with your Tableau Public account (free)
3. Your dashboard is now at: `public.tableau.com/app/profile/yourname`
4. Copy the embed link → paste into your GitHub README
5. Also add to your LinkedIn profile under Featured

**Important:** Tableau Public embeds data into the workbook on publish.
The PostgreSQL live connection becomes an extract (static snapshot).
This is expected and fine for portfolio purposes.

---

## Dashboard Design Tips

- Use **one accent colour** consistently (e.g. #1A6FA8 steel blue or Olist green #00A650)
- Grey (#888888) for all secondary/non-highlighted marks
- Font: Tableau Book or Calibri at 12pt for labels, 10pt for axis ticks
- KPI numbers: 24pt bold, label above in 10pt grey
- Add a thin horizontal divider between the KPI strip and chart area
- Every sheet title should state the business question, not just the chart type
  - ❌ "Bar Chart 1"
  - ✅ "Which states have the worst on-time delivery rate?"
