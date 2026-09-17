-- =========================================================
-- 03_etl.sql
-- ETL: Transaction Database (public schema) -> Data Warehouse (dwh schema)
--
-- Run after 01_create_oltp.sql + src/generate_data.py (data loaded)
-- and after 02_create_dwh.sql (warehouse tables created).
--
-- Order of operations matters: dimensions must be loaded before the
-- fact table, since fact_sales has FK references to every dimension.
-- Each load is idempotent (truncate-and-reload) so the script can be
-- re-run safely whenever the OLTP data changes.
-- =========================================================

-- ---------------------------------------------------------
-- 1. Load dim_category
-- Extract distinct categories, transform 1:1 (no reshaping needed).
-- ---------------------------------------------------------
TRUNCATE dwh.dim_category CASCADE;

INSERT INTO dwh.dim_category (category_id, category_name)
SELECT category_id, category_name
FROM categories;

-- ---------------------------------------------------------
-- 2. Load dim_product
-- ---------------------------------------------------------
TRUNCATE dwh.dim_product CASCADE;

INSERT INTO dwh.dim_product (product_id, product_name, list_price)
SELECT product_id, product_name, price
FROM products;

-- ---------------------------------------------------------
-- 3. Load dim_customer
-- ---------------------------------------------------------
TRUNCATE dwh.dim_customer CASCADE;

INSERT INTO dwh.dim_customer (customer_id, first_name, last_name, email, city, country, signup_date)
SELECT customer_id, first_name, last_name, email, city, country, signup_date
FROM customers;

-- ---------------------------------------------------------
-- 4. Load dim_date
-- Generate one row per calendar day covering the full range of
-- order dates present in the OLTP database (with a small buffer).
-- ---------------------------------------------------------
TRUNCATE dwh.dim_date CASCADE;

INSERT INTO dwh.dim_date (date_key, full_date, day, month, month_name, quarter, year, day_of_week, is_weekend)
SELECT
    (TO_CHAR(d, 'YYYYMMDD'))::INTEGER AS date_key,
    d::DATE AS full_date,
    EXTRACT(DAY FROM d)::SMALLINT AS day,
    EXTRACT(MONTH FROM d)::SMALLINT AS month,
    TO_CHAR(d, 'Month') AS month_name,
    EXTRACT(QUARTER FROM d)::SMALLINT AS quarter,
    EXTRACT(YEAR FROM d)::SMALLINT AS year,
    TO_CHAR(d, 'Day') AS day_of_week,
    (EXTRACT(ISODOW FROM d) IN (6, 7)) AS is_weekend
FROM generate_series(
    (SELECT MIN(order_date)::DATE FROM orders) - INTERVAL '1 day',
    (SELECT MAX(order_date)::DATE FROM orders) + INTERVAL '1 day',
    INTERVAL '1 day'
) AS d;

-- ---------------------------------------------------------
-- 5. Load fact_sales
-- Grain: one row per order_items row.
-- Joins order_items -> orders (date, status) -> customers -> products -> categories,
-- then resolves each natural key to its warehouse surrogate key.
-- total_amount is derived here (measure not stored redundantly in OLTP).
-- ---------------------------------------------------------
TRUNCATE dwh.fact_sales;

INSERT INTO dwh.fact_sales (
    order_id, order_item_id, date_key, customer_key, product_key, category_key,
    quantity, unit_price, discount, total_amount, order_status
)
SELECT
    oi.order_id,
    oi.order_item_id,
    (TO_CHAR(o.order_date, 'YYYYMMDD'))::INTEGER AS date_key,
    dc.customer_key,
    dp.product_key,
    dcat.category_key,
    oi.quantity,
    oi.unit_price,
    oi.discount_pct AS discount,
    ROUND(oi.quantity * oi.unit_price * (1 - oi.discount_pct), 2) AS total_amount,
    o.order_status
FROM order_items oi
JOIN orders o        ON o.order_id = oi.order_id
JOIN products p       ON p.product_id = oi.product_id
JOIN dwh.dim_customer dc ON dc.customer_id = o.customer_id
JOIN dwh.dim_product  dp ON dp.product_id = p.product_id
JOIN dwh.dim_category dcat ON dcat.category_id = p.category_id;
