import logging
import time
from flask import Flask, request, jsonify
from flask_cors import CORS
from prometheus_client import Counter, Histogram, make_wsgi_app, REGISTRY
from werkzeug.middleware.dispatcher import DispatcherMiddleware
import sqlite3
import os

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

REQUEST_COUNT = Counter(
    'flask_http_request_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)
REQUEST_LATENCY = Histogram(
    'flask_http_request_duration_seconds',
    'HTTP request latency',
    ['method', 'endpoint']
)

import tempfile
DB_PATH = os.environ.get('DB_PATH', os.path.join(tempfile.gettempdir(), 'products.db'))


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    with get_db() as conn:
        conn.execute('''
            CREATE TABLE IF NOT EXISTS products (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                price REAL NOT NULL,
                stock INTEGER NOT NULL
            )
        ''')
        if conn.execute('SELECT COUNT(*) FROM products').fetchone()[0] == 0:
            seed = [
                ('Laptop Pro 15"', 1299.99, 45),
                ('Wireless Keyboard', 89.99, 120),
                ('4K Monitor 27"', 449.99, 30),
                ('USB-C Hub 7-port', 59.99, 200),
                ('Mechanical Mouse', 129.99, 85),
            ]
            conn.executemany(
                'INSERT INTO products (name, price, stock) VALUES (?, ?, ?)', seed
            )


@app.before_request
def before_req():
    request._start_time = time.time()


@app.after_request
def after_req(response):
    latency = time.time() - getattr(request, '_start_time', time.time())
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.path,
        status=response.status_code
    ).inc()
    REQUEST_LATENCY.labels(
        method=request.method,
        endpoint=request.path
    ).observe(latency)
    logger.info('%s %s %s', request.method, request.path, response.status_code)
    return response


@app.route('/health')
def health():
    return jsonify({'status': 'ok', 'service': 'product-service'})


@app.route('/products', methods=['GET'])
def get_products():
    with get_db() as conn:
        rows = conn.execute('SELECT * FROM products').fetchall()
    return jsonify([dict(r) for r in rows])


@app.route('/products/<int:product_id>', methods=['GET'])
def get_product(product_id):
    with get_db() as conn:
        row = conn.execute(
            'SELECT * FROM products WHERE id = ?', (product_id,)
        ).fetchone()
    if row is None:
        return jsonify({'error': 'Product not found'}), 404
    return jsonify(dict(row))


@app.route('/products', methods=['POST'])
def create_product():
    data = request.get_json(force=True)
    name = data.get('name', '').strip()
    price = data.get('price')
    stock = data.get('stock', 0)
    if not name or price is None:
        return jsonify({'error': 'name and price are required'}), 400
    with get_db() as conn:
        cur = conn.execute(
            'INSERT INTO products (name, price, stock) VALUES (?, ?, ?)',
            (name, float(price), int(stock))
        )
        product_id = cur.lastrowid
    return jsonify({'id': product_id, 'name': name, 'price': price, 'stock': stock}), 201


app.wsgi_app = DispatcherMiddleware(app.wsgi_app, {'/metrics': make_wsgi_app()})

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5001, debug=os.environ.get('FLASK_ENV') == 'development')
