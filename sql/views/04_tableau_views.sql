-- ============================================================
-- OLIST — SQL VIEWS FOR TABLEAU DIRECT CONNECTION
-- File:    sql/views/04_tableau_views.sql
-- Purpose: Pre-built views that Tableau connects to directly.
--          Views encapsulate complex joins so Tableau stays fast.
--          Connect Tableau to these views, NOT raw tables.
-- ============================================================

SET search_path TO olist;

-- ============================================================
-- VIEW 1: v_orders_full
-- The master joined view — foundation for all Tableau worksheets
-- Includes: order + customer + delivery metrics + payment totals
-- ============================================================
CREATE OR REPLACE VIEW v_orders_full AS
SELECT
    -- Order identifiers
    o.order_id,
    o.order_status,
    -- Timestamps
    o.order_purchase_timestamp,
    DATE_TRUNC('month', o.order_purchase_timestamp)::DATE   AS order_month,
    DATE_TRUNC('week',  o.order_purchase_timestamp)::DATE   AS order_week,
    EXTRACT(YEAR  FROM o.order_purchase_timestamp)::INT      AS order_year,
    EXTRACT(MONTH FROM o.order_purchase_timestamp)::INT      AS order_month_num,
    EXTRACT(DOW   FROM o.order_purchase_timestamp)::INT      AS order_day_of_week, -- 0=Sun
    EXTRACT(HOUR  FROM o.order_purchase_timestamp)::INT      AS order_hour,
    -- Customer info
    o.customer_id,
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,
    c.customer_zip_code_prefix,
    -- Payment summary
    p.total_payment,
    p.payment_installments,
    p.payment_type,
    -- Item summary
    i.item_count,
    i.total_price,
    i.total_freight,
    ROUND(i.total_freight / NULLIF(i.total_price, 0) * 100, 2) AS freight_pct,
    -- Delivery metrics
    o.order_estimated_delivery_date,
    o.order_delivered_customer_date,
    EXTRACT(EPOCH FROM (
        o.order_delivered_customer_date - o.order_purchase_timestamp
    )) / 86400.0                                            AS actual_delivery_days,
    EXTRACT(EPOCH FROM (
        o.order_estimated_delivery_date - o.order_purchase_timestamp
    )) / 86400.0                                            AS promised_delivery_days,
    EXTRACT(EPOCH FROM (
        o.order_delivered_customer_date - o.order_estimated_delivery_date
    )) / 86400.0                                            AS delay_days,
    CASE
        WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date
            THEN 'On Time'
        ELSE 'Late'
    END                                                     AS delivery_status,
    -- Review
    r.review_score,
    CASE r.review_score
        WHEN 5 THEN 'Very Satisfied'
        WHEN 4 THEN 'Satisfied'
        WHEN 3 THEN 'Neutral'
        WHEN 2 THEN 'Dissatisfied'
        WHEN 1 THEN 'Very Dissatisfied'
    END                                                     AS review_label
FROM olist_orders o
JOIN olist_customers c ON o.customer_id = c.customer_id
LEFT JOIN (
    SELECT order_id,
           SUM(payment_value)    AS total_payment,
           MAX(payment_installments) AS payment_installments,
           STRING_AGG(DISTINCT payment_type, ', ') AS payment_type
    FROM olist_order_payments
    GROUP BY order_id
) p ON o.order_id = p.order_id
LEFT JOIN (
    SELECT order_id,
           COUNT(*)              AS item_count,
           SUM(price)            AS total_price,
           SUM(freight_value)    AS total_freight
    FROM olist_order_items
    GROUP BY order_id
) i ON o.order_id = i.order_id
LEFT JOIN (
    SELECT order_id, AVG(review_score) AS review_score
    FROM olist_order_reviews
    GROUP BY order_id
) r ON o.order_id = r.order_id;


-- ============================================================
-- VIEW 2: v_seller_metrics
-- Aggregated seller KPIs — feeds the Seller Performance page
-- ============================================================
CREATE OR REPLACE VIEW v_seller_metrics AS
SELECT
    s.seller_id,
    s.seller_state,
    s.seller_city,
    COUNT(DISTINCT oi.order_id)                     AS total_orders,
    COUNT(DISTINCT c.customer_unique_id)            AS unique_customers,
    ROUND(SUM(oi.price), 2)                         AS gross_revenue,
    ROUND(AVG(oi.price), 2)                         AS avg_item_price,
    ROUND(AVG(r.review_score), 3)                   AS avg_review_score,
    ROUND(AVG(
        EXTRACT(EPOCH FROM (
            o.order_delivered_carrier_date - o.order_purchase_timestamp
        )) / 86400.0
    ), 1)                                           AS avg_fulfillment_days,
    -- Revenue quartile for quadrant chart
    NTILE(4) OVER (ORDER BY SUM(oi.price) DESC)     AS revenue_quartile,
    NTILE(4) OVER (ORDER BY AVG(r.review_score) DESC) AS quality_quartile
FROM olist_sellers         s
JOIN olist_order_items     oi ON s.seller_id   = oi.seller_id
JOIN olist_orders           o  ON oi.order_id   = o.order_id
JOIN olist_customers        c  ON o.customer_id = c.customer_id
LEFT JOIN olist_order_reviews r ON o.order_id   = r.order_id
WHERE o.order_status = 'delivered'
GROUP BY s.seller_id, s.seller_state, s.seller_city
HAVING COUNT(DISTINCT oi.order_id) >= 5;


-- ============================================================
-- VIEW 3: v_category_performance
-- Category-level aggregation — feeds category charts
-- ============================================================
CREATE OR REPLACE VIEW v_category_performance AS
SELECT
    COALESCE(t.product_category_name_english,
             p.product_category_name, 'Unknown') AS category_english,
    p.product_category_name                       AS category_portuguese,
    COUNT(DISTINCT oi.order_id)                   AS total_orders,
    COUNT(DISTINCT oi.seller_id)                  AS unique_sellers,
    ROUND(SUM(oi.price), 2)                       AS gross_revenue,
    ROUND(AVG(oi.price), 2)                       AS avg_item_price,
    ROUND(AVG(oi.freight_value), 2)               AS avg_freight,
    ROUND(AVG(r.review_score), 3)                 AS avg_review_score,
    ROUND(
        SUM(oi.price) / SUM(SUM(oi.price)) OVER () * 100,
        2
    )                                             AS revenue_share_pct
FROM olist_order_items   oi
JOIN olist_orders         o  ON oi.order_id  = o.order_id
JOIN olist_products       p  ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation t
                             ON p.product_category_name = t.product_category_name
LEFT JOIN olist_order_reviews r ON o.order_id = r.order_id
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY 1, 2
ORDER BY gross_revenue DESC;


-- ============================================================
-- VIEW 4: v_geo_orders
-- State-level metrics with lat/lng for map visualizations
-- ============================================================
CREATE OR REPLACE VIEW v_geo_orders AS
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id)                    AS total_orders,
    ROUND(SUM(p.payment_value), 2)                AS total_gmv,
    ROUND(AVG(p.payment_value), 2)                AS avg_order_value,
    ROUND(AVG(r.review_score), 3)                 AS avg_review_score,
    ROUND(AVG(
        EXTRACT(EPOCH FROM (
            o.order_delivered_customer_date - o.order_estimated_delivery_date
        )) / 86400.0
    ), 1)                                         AS avg_delay_days,
    -- Representative lat/lng for each state (centroid approximation)
    AVG(g.geolocation_lat)                        AS state_lat,
    AVG(g.geolocation_lng)                        AS state_lng
FROM olist_orders          o
JOIN olist_customers        c   ON o.customer_id = c.customer_id
JOIN olist_order_payments   p   ON o.order_id    = p.order_id
LEFT JOIN olist_order_reviews r ON o.order_id    = r.order_id
LEFT JOIN olist_geolocation   g ON c.customer_zip_code_prefix = g.geolocation_zip_code_prefix
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY c.customer_state;


-- ============================================================
-- Confirm all views created successfully
-- ============================================================
SELECT viewname, schemaname
FROM pg_views
WHERE schemaname = 'olist'
ORDER BY viewname;
