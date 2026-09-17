-- =========================================================
-- 05_reporting_views.sql
-- Reporting views built on top of the dwh star schema.
-- Run after 03_etl.sql has populated fact_sales and the dimensions.
-- =========================================================

DROP VIEW IF EXISTS dwh.vw_sales_summary;
DROP VIEW IF EXISTS dwh.vw_product_performance;
DROP VIEW IF EXISTS dwh.vw_customer_performance;
DROP VIEW IF EXISTS dwh.vw_monthly_sales;

-- ---------------------------------------------------------
-- Sales Summary: per calendar date
-- ---------------------------------------------------------
CREATE VIEW dwh.vw_sales_summary AS
SELECT
    d.full_date                       AS order_date,
    COUNT(DISTINCT f.order_id)        AS total_orders,
    SUM(f.quantity)                   AS total_quantity_sold,
    SUM(f.total_amount)               AS total_revenue
FROM dwh.fact_sales f
JOIN dwh.dim_date d ON d.date_key = f.date_key
GROUP BY d.full_date
ORDER BY d.full_date;

-- ---------------------------------------------------------
-- Product Performance: per product, with its category
-- ---------------------------------------------------------
CREATE VIEW dwh.vw_product_performance AS
SELECT
    p.product_name,
    c.category_name,
    SUM(f.quantity)                   AS quantity_sold,
    SUM(f.total_amount)               AS revenue
FROM dwh.fact_sales f
JOIN dwh.dim_product p  ON p.product_key = f.product_key
JOIN dwh.dim_category c ON c.category_key = f.category_key
GROUP BY p.product_name, c.category_name
ORDER BY revenue DESC;

-- ---------------------------------------------------------
-- Customer Performance: per customer
-- ---------------------------------------------------------
CREATE VIEW dwh.vw_customer_performance AS
SELECT
    cu.customer_id,
    cu.first_name || ' ' || cu.last_name AS customer_name,
    COUNT(DISTINCT f.order_id)        AS number_of_orders,
    SUM(f.total_amount)               AS total_spending
FROM dwh.fact_sales f
JOIN dwh.dim_customer cu ON cu.customer_key = f.customer_key
GROUP BY cu.customer_id, customer_name
ORDER BY total_spending DESC;

-- ---------------------------------------------------------
-- Monthly Sales: per year/month
-- ---------------------------------------------------------
CREATE VIEW dwh.vw_monthly_sales AS
SELECT
    d.year,
    d.month,
    TRIM(d.month_name)                AS month_name,
    COUNT(DISTINCT f.order_id)        AS total_orders,
    SUM(f.total_amount)               AS total_revenue
FROM dwh.fact_sales f
JOIN dwh.dim_date d ON d.date_key = f.date_key
GROUP BY d.year, d.month, month_name
ORDER BY d.year, d.month;
