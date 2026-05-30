-- ============================================================
-- OLIST E-COMMERCE DATABASE SCHEMA
-- Project: Brazilian E-Commerce Business Performance Analysis
-- Author:  [Your Name]
-- Created: 2024
-- Tool:    PostgreSQL 15+ / SQL Workbench
-- ============================================================
-- Run this script FIRST before importing any CSV data.
-- Order matters: dimension tables before fact tables.
-- ============================================================

-- Create dedicated schema
CREATE SCHEMA IF NOT EXISTS olist;
SET search_path TO olist;

-- ============================================================
-- DIMENSION TABLES (no foreign key dependencies)
-- ============================================================

-- 1. Customers
DROP TABLE IF EXISTS olist_customers CASCADE;
CREATE TABLE olist_customers (
    customer_id             VARCHAR(50)  PRIMARY KEY,
    customer_unique_id      VARCHAR(50)  NOT NULL,   -- person-level ID (use for retention analysis)
    customer_zip_code_prefix VARCHAR(10) NOT NULL,
    customer_city           VARCHAR(100),
    customer_state          CHAR(2)      NOT NULL
);
-- Index for frequent joins and unique-customer analysis
CREATE INDEX idx_customers_unique_id ON olist_customers(customer_unique_id);
CREATE INDEX idx_customers_state     ON olist_customers(customer_state);

-- 2. Sellers
DROP TABLE IF EXISTS olist_sellers CASCADE;
CREATE TABLE olist_sellers (
    seller_id               VARCHAR(50)  PRIMARY KEY,
    seller_zip_code_prefix  VARCHAR(10),
    seller_city             VARCHAR(100),
    seller_state            CHAR(2)
);
CREATE INDEX idx_sellers_state ON olist_sellers(seller_state);

-- 3. Products
DROP TABLE IF EXISTS olist_products CASCADE;
CREATE TABLE olist_products (
    product_id                   VARCHAR(50)  PRIMARY KEY,
    product_category_name        VARCHAR(100),
    product_name_lenght          INTEGER,   -- intentional typo preserved from source
    product_description_lenght   INTEGER,
    product_photos_qty           INTEGER,
    product_weight_g             NUMERIC(10,2),
    product_length_cm            NUMERIC(10,2),
    product_height_cm            NUMERIC(10,2),
    product_width_cm             NUMERIC(10,2)
);
CREATE INDEX idx_products_category ON olist_products(product_category_name);

-- 4. Product Category Translation
DROP TABLE IF EXISTS product_category_name_translation CASCADE;
CREATE TABLE product_category_name_translation (
    product_category_name         VARCHAR(100) PRIMARY KEY,
    product_category_name_english VARCHAR(100) NOT NULL
);

-- 5. Geolocation (lookup table — large, 1M rows)
DROP TABLE IF EXISTS olist_geolocation CASCADE;
CREATE TABLE olist_geolocation (
    geolocation_zip_code_prefix VARCHAR(10)   NOT NULL,
    geolocation_lat             NUMERIC(15,8) NOT NULL,
    geolocation_lng             NUMERIC(15,8) NOT NULL,
    geolocation_city            VARCHAR(100),
    geolocation_state           CHAR(2)       NOT NULL
);
-- No PK (duplicates per zip exist). Index on zip for join performance.
CREATE INDEX idx_geo_zip   ON olist_geolocation(geolocation_zip_code_prefix);
CREATE INDEX idx_geo_state ON olist_geolocation(geolocation_state);

-- ============================================================
-- FACT TABLE
-- ============================================================

-- 6. Orders (central fact table — all analysis anchors here)
DROP TABLE IF EXISTS olist_orders CASCADE;
CREATE TABLE olist_orders (
    order_id                        VARCHAR(50)  PRIMARY KEY,
    customer_id                     VARCHAR(50)  NOT NULL REFERENCES olist_customers(customer_id),
    order_status                    VARCHAR(20)  NOT NULL,
    order_purchase_timestamp        TIMESTAMP,
    order_approved_at               TIMESTAMP,
    order_delivered_carrier_date    TIMESTAMP,
    order_delivered_customer_date   TIMESTAMP,
    order_estimated_delivery_date   TIMESTAMP
);
CREATE INDEX idx_orders_customer_id ON olist_orders(customer_id);
CREATE INDEX idx_orders_status      ON olist_orders(order_status);
CREATE INDEX idx_orders_purchase_ts ON olist_orders(order_purchase_timestamp);

-- ============================================================
-- BRIDGE / TRANSACTIONAL TABLES
-- ============================================================

-- 7. Order Items (one row per item within an order)
DROP TABLE IF EXISTS olist_order_items CASCADE;
CREATE TABLE olist_order_items (
    order_id            VARCHAR(50)   NOT NULL REFERENCES olist_orders(order_id),
    order_item_id       INTEGER       NOT NULL,   -- line number within order
    product_id          VARCHAR(50)   NOT NULL REFERENCES olist_products(product_id),
    seller_id           VARCHAR(50)   NOT NULL REFERENCES olist_sellers(seller_id),
    shipping_limit_date TIMESTAMP,
    price               NUMERIC(10,2) NOT NULL,
    freight_value       NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (order_id, order_item_id)
);
CREATE INDEX idx_items_product_id ON olist_order_items(product_id);
CREATE INDEX idx_items_seller_id  ON olist_order_items(seller_id);

-- 8. Order Payments (one order can have multiple payment methods)
DROP TABLE IF EXISTS olist_order_payments CASCADE;
CREATE TABLE olist_order_payments (
    order_id              VARCHAR(50)   NOT NULL REFERENCES olist_orders(order_id),
    payment_sequential    INTEGER       NOT NULL,
    payment_type          VARCHAR(30)   NOT NULL,
    payment_installments  INTEGER,
    payment_value         NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (order_id, payment_sequential)
);
CREATE INDEX idx_payments_type ON olist_order_payments(payment_type);

-- 9. Order Reviews
DROP TABLE IF EXISTS olist_order_reviews CASCADE;
CREATE TABLE olist_order_reviews (
    review_id                VARCHAR(50)  PRIMARY KEY,
    order_id                 VARCHAR(50)  NOT NULL REFERENCES olist_orders(order_id),
    review_score             SMALLINT     NOT NULL CHECK (review_score BETWEEN 1 AND 5),
    review_comment_title     TEXT,
    review_comment_message   TEXT,
    review_creation_date     TIMESTAMP,
    review_answer_timestamp  TIMESTAMP
);
CREATE INDEX idx_reviews_order_id ON olist_order_reviews(order_id);
CREATE INDEX idx_reviews_score    ON olist_order_reviews(review_score);

-- ============================================================
-- VERIFICATION QUERY — Run after import to validate
-- ============================================================
-- SELECT
--     'olist_customers'              AS tbl, COUNT(*) AS rows FROM olist.olist_customers UNION ALL
--     SELECT 'olist_sellers',                               COUNT(*) FROM olist.olist_sellers        UNION ALL
--     SELECT 'olist_products',                              COUNT(*) FROM olist.olist_products       UNION ALL
--     SELECT 'product_category_name_translation',           COUNT(*) FROM olist.product_category_name_translation UNION ALL
--     SELECT 'olist_geolocation',                           COUNT(*) FROM olist.olist_geolocation    UNION ALL
--     SELECT 'olist_orders',                                COUNT(*) FROM olist.olist_orders         UNION ALL
--     SELECT 'olist_order_items',                           COUNT(*) FROM olist.olist_order_items    UNION ALL
--     SELECT 'olist_order_payments',                        COUNT(*) FROM olist.olist_order_payments UNION ALL
--     SELECT 'olist_order_reviews',                         COUNT(*) FROM olist.olist_order_reviews;
-- Expected: 99441, 3095, 32951, 71, 1000163, 99441, 112650, 103886, 104719
