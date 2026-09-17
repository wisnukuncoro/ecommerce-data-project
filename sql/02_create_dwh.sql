-- =========================================================
-- 02_create_dwh.sql
-- Data warehouse schema: Star Schema
--
-- Grain of fact_sales: one row per product line item per order
-- (i.e. one row per order_items row in the OLTP database).
--
-- Dimensions use surrogate keys (dim_*_key) so the warehouse is
-- decoupled from OLTP identifiers and can absorb slowly changing
-- attributes later without breaking the fact table.
-- =========================================================

CREATE SCHEMA IF NOT EXISTS dwh;

DROP TABLE IF EXISTS dwh.fact_sales CASCADE;
DROP TABLE IF EXISTS dwh.dim_customer CASCADE;
DROP TABLE IF EXISTS dwh.dim_product CASCADE;
DROP TABLE IF EXISTS dwh.dim_category CASCADE;
DROP TABLE IF EXISTS dwh.dim_date CASCADE;

-- ---------------------------------------------------------
-- dim_customer
-- ---------------------------------------------------------
CREATE TABLE dwh.dim_customer (
    customer_key    SERIAL PRIMARY KEY,
    customer_id     INTEGER NOT NULL UNIQUE,     -- natural key from OLTP
    first_name      VARCHAR(50)  NOT NULL,
    last_name       VARCHAR(50)  NOT NULL,
    email           VARCHAR(150) NOT NULL,
    city            VARCHAR(100),
    country         VARCHAR(100),
    signup_date     DATE
);

-- ---------------------------------------------------------
-- dim_category
-- ---------------------------------------------------------
CREATE TABLE dwh.dim_category (
    category_key    SERIAL PRIMARY KEY,
    category_id     INTEGER NOT NULL UNIQUE,     -- natural key from OLTP
    category_name   VARCHAR(100) NOT NULL
);

-- ---------------------------------------------------------
-- dim_product
-- ---------------------------------------------------------
CREATE TABLE dwh.dim_product (
    product_key     SERIAL PRIMARY KEY,
    product_id      INTEGER NOT NULL UNIQUE,     -- natural key from OLTP
    product_name    VARCHAR(150) NOT NULL,
    list_price      NUMERIC(10,2) NOT NULL
);

-- ---------------------------------------------------------
-- dim_date
-- Surrogate key is a plain integer in YYYYMMDD form, which is
-- both human-readable and sorts/filters naturally.
-- ---------------------------------------------------------
CREATE TABLE dwh.dim_date (
    date_key        INTEGER PRIMARY KEY,         -- e.g. 20260315
    full_date       DATE NOT NULL UNIQUE,
    day             SMALLINT NOT NULL,
    month           SMALLINT NOT NULL,
    month_name      VARCHAR(15) NOT NULL,
    quarter         SMALLINT NOT NULL,
    year            SMALLINT NOT NULL,
    day_of_week     VARCHAR(15) NOT NULL,
    is_weekend      BOOLEAN NOT NULL
);

-- ---------------------------------------------------------
-- fact_sales
-- Grain: one row = one product within one order (order_items row)
-- ---------------------------------------------------------
CREATE TABLE dwh.fact_sales (
    sale_key        BIGSERIAL PRIMARY KEY,
    order_id        INTEGER NOT NULL,            -- degenerate dimension
    order_item_id   INTEGER NOT NULL UNIQUE,     -- degenerate dimension, grain guard

    date_key        INTEGER NOT NULL REFERENCES dwh.dim_date(date_key),
    customer_key    INTEGER NOT NULL REFERENCES dwh.dim_customer(customer_key),
    product_key     INTEGER NOT NULL REFERENCES dwh.dim_product(product_key),
    category_key    INTEGER NOT NULL REFERENCES dwh.dim_category(category_key),

    quantity        INTEGER NOT NULL,
    unit_price      NUMERIC(10,2) NOT NULL,
    discount        NUMERIC(4,2)  NOT NULL,
    total_amount    NUMERIC(12,2) NOT NULL,      -- quantity * unit_price * (1 - discount)

    order_status    VARCHAR(20) NOT NULL
);

CREATE INDEX idx_fact_sales_date_key ON dwh.fact_sales(date_key);
CREATE INDEX idx_fact_sales_customer_key ON dwh.fact_sales(customer_key);
CREATE INDEX idx_fact_sales_product_key ON dwh.fact_sales(product_key);
CREATE INDEX idx_fact_sales_category_key ON dwh.fact_sales(category_key);
