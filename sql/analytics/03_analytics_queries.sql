-- ============================================================
-- OLIST ANALYTICS — Core SQL Queries
-- File:    sql/analytics/03_analytics_queries.sql
-- Note:    All queries use olist schema. Set search_path first.
-- Fix:     All ROUND() calls cast to ::NUMERIC (PostgreSQL requirement)
-- ============================================================

SET search_path TO olist;

-- ============================================================
-- QUERY 1: Monthly GMV Trend (2016–2018)
-- ============================================================
WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC('month', o.order_purchase_timestamp)::DATE  AS order_month,
        COUNT(DISTINCT o.order_id)                             AS total_orders,
        COUNT(DISTINCT o.customer_id)                          AS unique_customers,
        SUM(p.payment_value)                                   AS gmv,
        ROUND(AVG(p.payment_value)::NUMERIC, 2)                AS avg_order_value,
        SUM(i.freight_value)                                   AS total_freight,
        ROUND(
            (SUM(i.freight_value) / NULLIF(SUM(p.payment_value), 0) * 100)::NUMERIC,
            2
        )                                                      AS freight_pct_of_gmv
    FROM olist_orders o
    JOIN olist_order_payments p ON o.order_id = p.order_id
    JOIN olist_order_items    i ON o.order_id = i.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
      AND o.order_purchase_timestamp IS NOT NULL
    GROUP BY 1
)
SELECT
    order_month,
    total_orders,
    unique_customers,
    ROUND(gmv::NUMERIC, 2)                                     AS gmv,
    avg_order_value,
    ROUND(freight_pct_of_gmv::NUMERIC, 1)                      AS freight_pct,
    ROUND(
        ((gmv - LAG(gmv) OVER (ORDER BY order_month))
        / NULLIF(LAG(gmv) OVER (ORDER BY order_month), 0) * 100)::NUMERIC,
        1
    )                                                          AS mom_growth_pct,
    ROUND(AVG(gmv) OVER (
        ORDER BY order_month
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    )::NUMERIC, 2)                                             AS rolling_3m_avg_gmv
FROM monthly_revenue
ORDER BY order_month;


-- ============================================================
-- QUERY 2: Revenue by Product Category
-- ============================================================
WITH category_revenue AS (
    SELECT
        COALESCE(t.product_category_name_english, p.product_category_name, 'Unknown')
                                          AS category,
        COUNT(DISTINCT o.order_id)        AS total_orders,
        COUNT(DISTINCT oi.seller_id)      AS unique_sellers,
        SUM(oi.price)                     AS gross_revenue,
        SUM(oi.freight_value)             AS total_freight,
        ROUND(AVG(oi.price)::NUMERIC, 2)           AS avg_item_price,
        ROUND(AVG(r.review_score)::NUMERIC, 2)     AS avg_review_score
    FROM olist_order_items   oi
    JOIN olist_orders         o  ON oi.order_id   = o.order_id
    JOIN olist_products       p  ON oi.product_id = p.product_id
    LEFT JOIN product_category_name_translation t
                                 ON p.product_category_name = t.product_category_name
    LEFT JOIN olist_order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY 1
),
ranked AS (
    SELECT *,
        RANK() OVER (ORDER BY gross_revenue DESC)  AS revenue_rank,
        RANK() OVER (ORDER BY total_orders DESC)   AS volume_rank,
        ROUND((gross_revenue / SUM(gross_revenue) OVER () * 100)::NUMERIC, 2)
                                                   AS revenue_share_pct
    FROM category_revenue
)
SELECT
    revenue_rank,
    category,
    total_orders,
    unique_sellers,
    ROUND(gross_revenue::NUMERIC, 2)   AS gross_revenue,
    revenue_share_pct,
    avg_item_price,
    avg_review_score,
    volume_rank,
    CASE
        WHEN revenue_rank <= 10 AND volume_rank <= 10 THEN 'Star (high revenue + high volume)'
        WHEN revenue_rank <= 10                       THEN 'Premium (high revenue, lower volume)'
        WHEN volume_rank <= 10                        THEN 'Mass (high volume, lower revenue)'
        ELSE 'Long tail'
    END                                AS category_segment
FROM ranked
ORDER BY revenue_rank
LIMIT 30;


-- ============================================================
-- QUERY 3: Delivery Performance by State
-- ============================================================
WITH delivery_data AS (
    SELECT
        o.order_id,
        c.customer_state,
        s.seller_state,
        EXTRACT(EPOCH FROM (
            o.order_delivered_customer_date - o.order_purchase_timestamp
        )) / 86400.0                        AS actual_delivery_days,
        EXTRACT(EPOCH FROM (
            o.order_delivered_customer_date - o.order_estimated_delivery_date
        )) / 86400.0                        AS delay_days
    FROM olist_orders         o
    JOIN olist_customers      c  ON o.customer_id = c.customer_id
    JOIN olist_order_items    oi ON o.order_id    = oi.order_id
    JOIN olist_sellers        s  ON oi.seller_id  = s.seller_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)
SELECT
    customer_state,
    COUNT(*)                                                        AS total_delivered,
    ROUND(AVG(actual_delivery_days)::NUMERIC, 1)                    AS avg_delivery_days,
    ROUND(AVG(delay_days)::NUMERIC, 1)                              AS avg_delay_days,
    ROUND(
        SUM(CASE WHEN delay_days <= 0 THEN 1 ELSE 0 END)::NUMERIC
        / COUNT(*) * 100,
        1
    )                                                               AS on_time_rate_pct,
    SUM(CASE WHEN delay_days > 0 THEN 1 ELSE 0 END)                AS late_orders,
    SUM(CASE WHEN delay_days < 0 THEN 1 ELSE 0 END)                AS early_orders,
    SUM(CASE WHEN delay_days > 7 THEN 1 ELSE 0 END)                AS severely_late_orders,
    ROUND(MAX(delay_days)::NUMERIC, 0)                              AS worst_delay_days
FROM delivery_data
GROUP BY customer_state
ORDER BY avg_delay_days DESC;


-- ============================================================
-- QUERY 4: Review Score vs Delivery Delay Correlation
-- ============================================================
WITH order_performance AS (
    SELECT
        o.order_id,
        r.review_score,
        EXTRACT(EPOCH FROM (
            o.order_delivered_customer_date - o.order_estimated_delivery_date
        )) / 86400.0                          AS delay_days,
        CASE
            WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date
                THEN 'On time or early'
            WHEN EXTRACT(EPOCH FROM (
                    o.order_delivered_customer_date - o.order_estimated_delivery_date
                )) / 86400.0 <= 3
                THEN 'Slightly late (1-3 days)'
            WHEN EXTRACT(EPOCH FROM (
                    o.order_delivered_customer_date - o.order_estimated_delivery_date
                )) / 86400.0 <= 7
                THEN 'Late (4-7 days)'
            ELSE 'Very late (>7 days)'
        END                                   AS delivery_bucket
    FROM olist_orders        o
    JOIN olist_order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)
SELECT
    delivery_bucket,
    COUNT(*)                                            AS order_count,
    ROUND(AVG(review_score)::NUMERIC, 3)                AS avg_review_score,
    ROUND(
        (AVG(review_score) - (SELECT AVG(review_score) FROM order_performance))::NUMERIC,
        3
    )                                                   AS score_vs_overall_avg,
    ROUND(
        SUM(CASE WHEN review_score = 1 THEN 1 ELSE 0 END)::NUMERIC / COUNT(*) * 100,
        1
    )                                                   AS pct_1_star,
    ROUND(
        SUM(CASE WHEN review_score = 5 THEN 1 ELSE 0 END)::NUMERIC / COUNT(*) * 100,
        1
    )                                                   AS pct_5_star
FROM order_performance
GROUP BY delivery_bucket
ORDER BY avg_review_score DESC;


-- ============================================================
-- QUERY 5: Seller Performance Ranking
-- ============================================================
WITH seller_metrics AS (
    SELECT
        s.seller_id,
        s.seller_state,
        s.seller_city,
        COUNT(DISTINCT o.order_id)                      AS total_orders,
        COUNT(DISTINCT o.customer_id)                   AS unique_customers,
        ROUND(SUM(oi.price)::NUMERIC, 2)                AS gross_revenue,
        ROUND(AVG(oi.price)::NUMERIC, 2)                AS avg_item_price,
        ROUND(AVG(r.review_score)::NUMERIC, 3)          AS avg_review_score,
        COUNT(r.review_id)                              AS review_count,
        ROUND(AVG(
            EXTRACT(EPOCH FROM (
                o.order_delivered_carrier_date - o.order_purchase_timestamp
            )) / 86400.0
        )::NUMERIC, 1)                                  AS avg_fulfillment_days,
        ROUND(COUNT(r.review_id)::NUMERIC / COUNT(DISTINCT o.order_id) * 100, 1)
                                                        AS review_rate_pct
    FROM olist_sellers          s
    JOIN olist_order_items      oi ON s.seller_id  = oi.seller_id
    JOIN olist_orders            o ON oi.order_id   = o.order_id
    LEFT JOIN olist_order_reviews r ON o.order_id   = r.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY s.seller_id, s.seller_state, s.seller_city
    HAVING COUNT(DISTINCT o.order_id) >= 10
),
ranked_sellers AS (
    SELECT *,
        RANK()   OVER (ORDER BY gross_revenue     DESC) AS revenue_rank,
        NTILE(4) OVER (ORDER BY gross_revenue     DESC) AS revenue_quartile,
        NTILE(4) OVER (ORDER BY avg_review_score  DESC) AS quality_quartile
    FROM seller_metrics
)
SELECT
    revenue_rank,
    seller_id,
    seller_state,
    total_orders,
    unique_customers,
    gross_revenue,
    avg_item_price,
    avg_review_score,
    avg_fulfillment_days,
    CASE
        WHEN revenue_quartile = 1 AND quality_quartile = 1 THEN 'Champion'
        WHEN revenue_quartile = 1 AND quality_quartile >= 3 THEN 'High Revenue Low Quality'
        WHEN revenue_quartile >= 3 AND quality_quartile = 1 THEN 'Rising Star'
        WHEN revenue_quartile >= 3 AND quality_quartile >= 3 THEN 'At Risk'
        ELSE 'Average'
    END                                                   AS seller_segment
FROM ranked_sellers
ORDER BY revenue_rank
LIMIT 50;


-- ============================================================
-- QUERY 6: RFM Customer Segmentation
-- ============================================================
WITH customer_rfm AS (
    SELECT
        c.customer_unique_id,
        MAX(o.order_purchase_timestamp)         AS last_order_date,
        COUNT(DISTINCT o.order_id)              AS frequency,
        ROUND(SUM(p.payment_value)::NUMERIC, 2) AS monetary
    FROM olist_customers      c
    JOIN olist_orders         o ON c.customer_id = o.customer_id
    JOIN olist_order_payments p ON o.order_id    = p.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY c.customer_unique_id
),
rfm_scores AS (
    SELECT
        customer_unique_id,
        DATE_PART('day', DATE '2018-10-17' - last_order_date::DATE) AS recency_days,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY last_order_date DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency    ASC)     AS f_score,
        NTILE(5) OVER (ORDER BY monetary     ASC)     AS m_score
    FROM customer_rfm
)
SELECT
    customer_unique_id,
    recency_days,
    frequency,
    ROUND(monetary::NUMERIC, 2)                          AS monetary,
    r_score,
    f_score,
    m_score,
    ROUND(((r_score + f_score + m_score) / 3.0)::NUMERIC, 2) AS rfm_avg,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3                  THEN 'Loyal Customers'
        WHEN r_score >= 4 AND f_score <= 2                  THEN 'Recent Customers'
        WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3 THEN 'At Risk'
        WHEN r_score <= 2 AND f_score <= 2                  THEN 'Churned'
        ELSE 'Potential Loyalists'
    END                                                  AS rfm_segment
FROM rfm_scores
ORDER BY rfm_avg DESC;


-- ============================================================
-- QUERY 7: Customer Retention & Repeat Purchase Rate
-- ============================================================
WITH customer_order_counts AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id)      AS order_count,
        MIN(o.order_purchase_timestamp) AS first_order,
        MAX(o.order_purchase_timestamp) AS last_order
    FROM olist_customers c
    JOIN olist_orders    o ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY c.customer_unique_id
)
SELECT
    COUNT(*)                                                    AS total_unique_customers,
    SUM(CASE WHEN order_count = 1  THEN 1 ELSE 0 END)          AS one_time_buyers,
    SUM(CASE WHEN order_count >= 2 THEN 1 ELSE 0 END)          AS repeat_buyers,
    ROUND(
        SUM(CASE WHEN order_count >= 2 THEN 1 ELSE 0 END)::NUMERIC
        / COUNT(*) * 100,
        2
    )                                                           AS repeat_purchase_rate_pct,
    ROUND(AVG(order_count)::NUMERIC, 3)                         AS avg_orders_per_customer,
    MAX(order_count)                                            AS max_orders_single_customer
FROM customer_order_counts;


-- ============================================================
-- QUERY 8: Freight Cost Efficiency by State
-- ============================================================
SELECT
    c.customer_state,
    COUNT(DISTINCT o.order_id)                              AS total_orders,
    ROUND(AVG(oi.price)::NUMERIC, 2)                        AS avg_item_price,
    ROUND(AVG(oi.freight_value)::NUMERIC, 2)                AS avg_freight,
    ROUND(
        (AVG(oi.freight_value / NULLIF(oi.price, 0)) * 100)::NUMERIC,
        1
    )                                                       AS freight_pct_of_price,
    ROUND(SUM(oi.freight_value)::NUMERIC, 2)                AS total_freight_revenue,
    CASE
        WHEN AVG(oi.freight_value / NULLIF(oi.price, 0)) > 0.25
            THEN 'High freight burden (>25% of price)'
        WHEN AVG(oi.freight_value / NULLIF(oi.price, 0)) > 0.15
            THEN 'Moderate freight burden'
        ELSE 'Efficient freight (<15% of price)'
    END                                                     AS freight_efficiency
FROM olist_order_items oi
JOIN olist_orders       o ON oi.order_id   = o.order_id
JOIN olist_customers    c ON o.customer_id = c.customer_id
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY c.customer_state
ORDER BY freight_pct_of_price DESC;
