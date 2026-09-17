-- =========================================================
-- 01_create_oltp.sql
-- Transaction (OLTP) database schema for the E-Commerce system
-- Normalized to 3NF: no repeating groups, no derived/duplicated
-- columns (e.g. line totals are computed, not stored).
-- =========================================================

DROP TABLE IF EXISTS payments CASCADE;
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS customers CASCADE;

-- ---------------------------------------------------------
-- categories
-- ---------------------------------------------------------
CREATE TABLE categories (
    category_id     SERIAL PRIMARY KEY,
    category_name   VARCHAR(100) NOT NULL UNIQUE
);

-- ---------------------------------------------------------
-- customers
-- ---------------------------------------------------------
CREATE TABLE customers (
    customer_id     SERIAL PRIMARY KEY,
    first_name      VARCHAR(50)  NOT NULL,
    last_name       VARCHAR(50)  NOT NULL,
    email           VARCHAR(150) NOT NULL UNIQUE,
    phone           VARCHAR(30),
    city            VARCHAR(100),
    country         VARCHAR(100),
    signup_date     DATE NOT NULL
);

-- ---------------------------------------------------------
-- products
-- ---------------------------------------------------------
CREATE TABLE products (
    product_id      SERIAL PRIMARY KEY,
    category_id     INTEGER NOT NULL REFERENCES categories(category_id),
    product_name    VARCHAR(150) NOT NULL,
    price           NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE INDEX idx_products_category_id ON products(category_id);

-- ---------------------------------------------------------
-- orders
-- ---------------------------------------------------------
CREATE TABLE orders (
    order_id        SERIAL PRIMARY KEY,
    customer_id     INTEGER NOT NULL REFERENCES customers(customer_id),
    order_date      TIMESTAMP NOT NULL,
    order_status    VARCHAR(20) NOT NULL
        CHECK (order_status IN ('pending', 'completed', 'cancelled', 'refunded'))
);

CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_order_date ON orders(order_date);

-- ---------------------------------------------------------
-- order_items  (one row per product line within an order)
-- ---------------------------------------------------------
CREATE TABLE order_items (
    order_item_id   SERIAL PRIMARY KEY,
    order_id        INTEGER NOT NULL REFERENCES orders(order_id),
    product_id      INTEGER NOT NULL REFERENCES products(product_id),
    quantity        INTEGER NOT NULL CHECK (quantity > 0),
    unit_price      NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0), -- price at time of sale
    discount_pct    NUMERIC(4,2)  NOT NULL DEFAULT 0 CHECK (discount_pct BETWEEN 0 AND 1)
);

CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_order_items_product_id ON order_items(product_id);

-- ---------------------------------------------------------
-- payments (one payment per order)
-- ---------------------------------------------------------
CREATE TABLE payments (
    payment_id      SERIAL PRIMARY KEY,
    order_id        INTEGER NOT NULL REFERENCES orders(order_id),
    payment_date    TIMESTAMP NOT NULL,
    payment_method  VARCHAR(20) NOT NULL
        CHECK (payment_method IN ('credit_card', 'debit_card', 'bank_transfer', 'e_wallet', 'cod')),
    amount          NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    payment_status  VARCHAR(20) NOT NULL
        CHECK (payment_status IN ('paid', 'pending', 'failed', 'refunded'))
);

CREATE INDEX idx_payments_order_id ON payments(order_id);
