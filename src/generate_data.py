"""
generate_data.py

Populates the OLTP e-commerce database (created by sql/01_create_oltp.sql)
with realistic dummy data using Faker.

Usage:
    python src/generate_data.py

Connection settings are read from environment variables (with sane
defaults for local development):
    PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD
"""

import os
import random
from datetime import datetime, timedelta

import psycopg
from faker import Faker

fake = Faker()
random.seed(42)
Faker.seed(42)

N_CATEGORIES = 10
N_PRODUCTS = 50
N_CUSTOMERS = 100
N_ORDERS = 500

ORDER_STATUSES = ["completed", "pending", "cancelled", "refunded"]
ORDER_STATUS_WEIGHTS = [0.75, 0.10, 0.10, 0.05]

PAYMENT_METHODS = ["credit_card", "debit_card", "bank_transfer", "e_wallet", "cod"]

CATEGORY_NAMES = [
    "Electronics", "Home & Kitchen", "Fashion", "Sports & Outdoors",
    "Books", "Beauty & Personal Care", "Toys & Games", "Groceries",
    "Automotive", "Office Supplies",
]

# Rough price bands per category so products look realistic.
CATEGORY_PRICE_RANGE = {
    "Electronics": (50, 2000),
    "Home & Kitchen": (10, 500),
    "Fashion": (10, 250),
    "Sports & Outdoors": (15, 400),
    "Books": (5, 60),
    "Beauty & Personal Care": (5, 150),
    "Toys & Games": (5, 200),
    "Groceries": (2, 80),
    "Automotive": (10, 900),
    "Office Supplies": (2, 300),
}


def get_connection():
    return psycopg.connect(
        host=os.getenv("PGHOST", "localhost"),
        port=os.getenv("PGPORT", "5432"),
        dbname=os.getenv("PGDATABASE", "ecommerce"),
        user=os.getenv("PGUSER", "postgres"),
        password=os.getenv("PGPASSWORD", "postgres"),
    )


def reset_tables(cur):
    cur.execute(
        "TRUNCATE payments, order_items, orders, products, categories, customers "
        "RESTART IDENTITY CASCADE;"
    )


def insert_categories(cur):
    rows = [(name,) for name in CATEGORY_NAMES]
    cur.executemany("INSERT INTO categories (category_name) VALUES (%s)", rows)
    # Table was just TRUNCATEd with RESTART IDENTITY, so ids are assigned
    # sequentially in insertion order -> safe to derive them without RETURNING.
    ids = list(range(1, len(CATEGORY_NAMES) + 1))
    return dict(zip(CATEGORY_NAMES, ids))


def insert_customers(cur, n):
    rows = []
    for _ in range(n):
        first = fake.first_name()
        last = fake.last_name()
        email = f"{first.lower()}.{last.lower()}{random.randint(1, 9999)}@{fake.free_email_domain()}"
        signup_date = fake.date_between(start_date="-3y", end_date="-1M")
        rows.append(
            (first, last, email, fake.phone_number()[:30], fake.city(), fake.country(), signup_date)
        )
    cur.executemany(
        "INSERT INTO customers (first_name, last_name, email, phone, city, country, signup_date) "
        "VALUES (%s, %s, %s, %s, %s, %s, %s)",
        rows,
    )
    return list(range(1, n + 1))


PRODUCT_ADJECTIVES = ["Premium", "Classic", "Pro", "Essential", "Compact", "Deluxe", "Eco", "Smart", "Ultra", "Basic"]


def insert_products(cur, category_ids_by_name, n):
    category_names = list(category_ids_by_name.keys())
    rows = []
    for _ in range(n):
        cat_name = random.choice(category_names)
        cat_id = category_ids_by_name[cat_name]
        low, high = CATEGORY_PRICE_RANGE[cat_name]
        price = round(random.uniform(low, high), 2)
        name = f"{random.choice(PRODUCT_ADJECTIVES)} {fake.word().capitalize()} {cat_name.split(' ')[0]}"
        rows.append((cat_id, name, price, random.random() > 0.05))
    cur.executemany(
        "INSERT INTO products (category_id, product_name, price, is_active) VALUES (%s, %s, %s, %s)",
        rows,
    )
    return list(range(1, n + 1))


def insert_orders(cur, customer_ids, n):
    start = datetime.now() - timedelta(days=450)
    end = datetime.now()
    rows = []
    for _ in range(n):
        customer_id = random.choice(customer_ids)
        order_date = fake.date_time_between(start_date=start, end_date=end)
        status = random.choices(ORDER_STATUSES, weights=ORDER_STATUS_WEIGHTS, k=1)[0]
        rows.append((customer_id, order_date, status))
    cur.executemany(
        "INSERT INTO orders (customer_id, order_date, order_status) VALUES (%s, %s, %s)",
        rows,
    )
    # order_ids are sequential 1..n in insertion order (see note in insert_categories)
    return [(i + 1, order_date, status) for i, (_, order_date, status) in enumerate(rows)]


def insert_order_items_and_payments(cur, orders, products):
    """products: list of (product_id, price)"""
    item_rows = []
    order_totals = {}

    for order_id, order_date, status in orders:
        n_items = random.randint(1, 5)
        chosen_products = random.sample(products, k=min(n_items, len(products)))
        order_total = 0
        for product_id, base_price in chosen_products:
            quantity = random.randint(1, 5)
            # small realistic variance around list price (promotions, price drift)
            unit_price = round(base_price * random.uniform(0.95, 1.05), 2)
            discount_pct = random.choices(
                [0, 0.05, 0.10, 0.15, 0.20, 0.30],
                weights=[0.55, 0.15, 0.12, 0.10, 0.05, 0.03],
                k=1,
            )[0]
            line_total = round(quantity * unit_price * (1 - discount_pct), 2)
            order_total += line_total
            item_rows.append((order_id, product_id, quantity, unit_price, discount_pct))
        order_totals[order_id] = (round(order_total, 2), order_date, status)

    cur.executemany(
        "INSERT INTO order_items (order_id, product_id, quantity, unit_price, discount_pct) VALUES (%s, %s, %s, %s, %s)",
        item_rows,
    )

    payment_rows = []
    for order_id, (total, order_date, status) in order_totals.items():
        payment_date = order_date + timedelta(hours=random.randint(0, 48))
        if status == "completed":
            payment_status = "paid"
        elif status == "cancelled":
            payment_status = random.choice(["failed", "refunded"])
        elif status == "refunded":
            payment_status = "refunded"
        else:  # pending
            payment_status = "pending"
        payment_rows.append(
            (order_id, payment_date, random.choice(PAYMENT_METHODS), total, payment_status)
        )

    cur.executemany(
        "INSERT INTO payments (order_id, payment_date, payment_method, amount, payment_status) VALUES (%s, %s, %s, %s, %s)",
        payment_rows,
    )

    return len(item_rows), len(payment_rows)


def main():
    conn = get_connection()
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            reset_tables(cur)

            category_ids_by_name = insert_categories(cur)
            print(f"Inserted {len(category_ids_by_name)} categories")

            customer_ids = insert_customers(cur, N_CUSTOMERS)
            print(f"Inserted {len(customer_ids)} customers")

            product_ids = insert_products(cur, category_ids_by_name, N_PRODUCTS)
            print(f"Inserted {len(product_ids)} products")

            cur.execute("SELECT product_id, price FROM products")
            products = [(pid, float(price)) for pid, price in cur.fetchall()]

            orders = insert_orders(cur, customer_ids, N_ORDERS)
            print(f"Inserted {len(orders)} orders")

            n_items, n_payments = insert_order_items_and_payments(cur, orders, products)
            print(f"Inserted {n_items} order_items")
            print(f"Inserted {n_payments} payments")

        conn.commit()
        print("Done. Data committed.")
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
