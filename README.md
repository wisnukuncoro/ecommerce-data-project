# E-Commerce Data Engineering Project

A small, practical end-to-end data engineering project: a normalized
transaction (OLTP) database for a fictional e-commerce business, a star-schema
data warehouse built from it, a simple SQL ETL process, and a set of
reporting views for analysis.

## 1. Project Overview

```text
Transaction Database (OLTP, PostgreSQL, "public" schema)
        |
        v
       ETL  (sql/03_etl.sql)
        |
        v
 Data Warehouse (Star Schema, "dwh" schema)
        |
        v
 Reporting Views (dwh.vw_*)
```

Scenario: customers browse products (grouped into categories), place
orders, each order has one or more line items, and each order is paid
for once. The OLTP schema captures that as it happens; the warehouse
reshapes it for fast, simple analytical queries.

## 2. Database Structure (OLTP)

Tables: `customers`, `categories`, `products`, `orders`, `order_items`, `payments`.

```
customers → orders → order_items → products → categories
orders → payments
```

Normalized to 3NF — every attribute is stored once, in the table it
describes. See [docs/data_model.md](docs/data_model.md) for the full ERD
and the reasoning behind it (e.g. why `unit_price` is copied onto
`order_items` rather than always reading `products.price`).

## 3. Data Warehouse Structure

Star schema in the `dwh` Postgres schema:

- **Fact:** `fact_sales` — grain is **one row per product per order**
  (one row per OLTP `order_items` row). Measures: `quantity`, `unit_price`,
  `discount`, `total_amount`.
- **Dimensions:** `dim_customer`, `dim_product`, `dim_category`, `dim_date`,
  each with a surrogate key.

Full diagram and design rationale: [docs/data_model.md](docs/data_model.md).

## 4. ETL Process

Implemented in plain SQL (`sql/03_etl.sql`), run directly against Postgres —
no external orchestration needed for a project this size.

1. **Extract** — read from the OLTP tables (`customers`, `categories`,
   `products`, `orders`, `order_items`).
2. **Transform** — resolve OLTP natural keys to warehouse surrogate keys,
   derive `date_key` from `order_date`, and compute `total_amount =
   quantity * unit_price * (1 - discount)`.
3. **Load dimensions** first (`dim_category`, `dim_product`, `dim_customer`,
   `dim_date`), then **load the fact table** (`fact_sales`), since it has
   foreign keys into every dimension.

Each step truncates and reloads its target table, so the script is
idempotent and safe to re-run after regenerating data.

## 5. Reporting Views

All in the `dwh` schema, built on top of `fact_sales` (`sql/05_reporting_views.sql`):

| View | Grain | Shows |
|---|---|---|
| `dwh.vw_sales_summary` | per date | total orders, total quantity sold, total revenue |
| `dwh.vw_product_performance` | per product | category, quantity sold, revenue |
| `dwh.vw_customer_performance` | per customer | number of orders, total spending |
| `dwh.vw_monthly_sales` | per year/month | total orders, total revenue |

## 6. How to Run

Requires PostgreSQL (tested on 14) and Python 3.10+.

```bash
# 1. Create the database
createdb ecommerce

# 2. Create the OLTP schema
psql -d ecommerce -f sql/01_create_oltp.sql

# 3. Generate and load realistic dummy data
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
PGHOST=localhost PGPORT=5432 PGDATABASE=ecommerce PGUSER=<your_user> PGPASSWORD=<your_password> \
  python src/generate_data.py

# 4. Create the data warehouse schema
psql -d ecommerce -f sql/02_create_dwh.sql

# 5. Run the ETL (OLTP -> DWH)
psql -d ecommerce -f sql/03_etl.sql

# 6. Create the reporting views
psql -d ecommerce -f sql/05_reporting_views.sql

# 7. Query a report
psql -d ecommerce -c "SELECT * FROM dwh.vw_monthly_sales;"
```

This has been run end-to-end locally: 10 categories, 100 customers, 50
products, 500 orders, ~1,500 order items, 500 payments, producing 1,500
fact rows and sensible aggregates in all four views.

## 7. Project Structure

```text
ecommerce-data-project/
│
├── README.md
├── requirements.txt
│
├── sql/
│   ├── 01_create_oltp.sql       -- OLTP schema (tables, keys, indexes)
│   ├── 02_create_dwh.sql        -- Star schema (dims + fact)
│   ├── 03_etl.sql                -- OLTP -> DWH transform/load
│   └── 05_reporting_views.sql   -- Reporting views
│
├── src/
│   └── generate_data.py         -- Realistic dummy data generator (Faker)
│
└── docs/
    └── data_model.md            -- ERD + design rationale
```

## 8. Key Design Decisions

- **SQL for the ETL, Python only for data generation.** The transform logic
  (key lookups, derived measures) is a handful of `INSERT ... SELECT ...
  JOIN` statements — plain SQL is more transparent and easier to audit than
  wrapping the same joins in a Python/pandas layer. Python is used only
  where it earns its keep: generating varied, realistic fake data with Faker.
- **Same Postgres instance, two schemas (`public` for OLTP, `dwh` for the
  warehouse)**, rather than two separate databases. Keeps the project
  runnable with a single connection while still cleanly separating
  operational and analytical tables.
- **Truncate-and-reload ETL**, not incremental/upsert logic. At this data
  volume a full reload runs in well under a second, and idempotent
  full reloads are simpler to reason about and re-run than tracking
  high-water marks — the added complexity of incremental loads isn't
  justified here.
- **`order_items` grain for `fact_sales`.** This is the lowest grain that's
  actually useful for the required reports (sales by date, by product, by
  customer, by month); a finer grain doesn't exist in the source data, and
  a coarser grain (e.g. one row per order) would make product/category
  reporting impossible.
- **Surrogate keys in every dimension, natural keys kept alongside.** Makes
  the warehouse independent of OLTP id churn and is the standard,
  well-understood approach for star schemas — even though this project
  doesn't yet need slowly-changing-dimension handling, the surrogate key
  is what would make adding it later a non-breaking change.
- **`total_amount` stored on the fact row, not computed at query time.**
  It's a straightforward derived measure (`quantity * unit_price * (1 -
  discount)`), and every reporting view needs it, so computing it once
  during ETL keeps the views simple `SUM()`s instead of repeating the
  formula in four places.
