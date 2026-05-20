import logging
import time
import os
import sqlite3
from datetime import datetime

import requests
from flask import Flask, request, jsonify
from flask_cors import CORS
from prometheus_client import Counter, Histogram, make_wsgi_app
from werkzeug.middleware.dispatcher import DispatcherMiddleware

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

PRODUCT_SERVICE_URL = os.environ.get('PRODUCT_SERVICE_URL', 'http://localhost:5001')
import tempfile
DB_PATH = os.environ.get('DB_PATH', os.path.join(tempfile.gettempdir(), 'orders.db'))

ORDERS_CREATED = Counter(
    'orders_created_total',
    'Total number of orders created'
)
ORDER_PROCESSING = Histogram(
    'order_processing_seconds',
    'Time spent processing an order',
    buckets=[0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5]
)
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


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    with get_db() as conn:
        conn.execute('''
            CREATE TABLE IF NOT EXISTS orders (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                product_id INTEGER NOT NULL,
                quantity INTEGER NOT NULL,
                status TEXT NOT NULL DEFAULT 'pending',
                created_at TEXT NOT NULL
            )
        ''')


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
    return jsonify({'status': 'ok', 'service': 'order-service'})


@app.route('/orders', methods=['GET'])
def get_orders():
    with get_db() as conn:
        rows = conn.execute('SELECT * FROM orders ORDER BY id DESC').fetchall()
    return jsonify([dict(r) for r in rows])


@app.route('/orders/<int:order_id>', methods=['GET'])
def get_order(order_id):
    with get_db() as conn:
        row = conn.execute(
            'SELECT * FROM orders WHERE id = ?', (order_id,)
        ).fetchone()
    if row is None:
        return jsonify({'error': 'Order not found'}), 404
    return jsonify(dict(row))


@app.route('/orders', methods=['POST'])
def create_order():
    start = time.time()
    data = request.get_json(force=True)
    product_id = data.get('product_id')
    quantity = data.get('quantity', 1)

    if not product_id:
        return jsonify({'error': 'product_id is required'}), 400
    if int(quantity) < 1:
        return jsonify({'error': 'quantity must be at least 1'}), 400

    try:
        resp = requests.get(
            f'{PRODUCT_SERVICE_URL}/products/{product_id}', timeout=5
        )
        if resp.status_code == 404:
            return jsonify({'error': f'Product {product_id} does not exist'}), 422
        resp.raise_for_status()
    except requests.exceptions.RequestException as e:
        logger.error('Product service unreachable: %s', e)
        return jsonify({'error': 'Product service unavailable'}), 503

    created_at = datetime.utcnow().isoformat()
    with get_db() as conn:
        cur = conn.execute(
            'INSERT INTO orders (product_id, quantity, status, created_at) VALUES (?, ?, ?, ?)',
            (int(product_id), int(quantity), 'confirmed', created_at)
        )
        order_id = cur.lastrowid

    ORDERS_CREATED.inc()
    ORDER_PROCESSING.observe(time.time() - start)

    return jsonify({
        'id': order_id,
        'product_id': int(product_id),
        'quantity': int(quantity),
        'status': 'confirmed',
        'created_at': created_at
    }), 201


app.wsgi_app = DispatcherMiddleware(app.wsgi_app, {'/metrics': make_wsgi_app()})

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5002, debug=os.environ.get('FLASK_ENV') == 'development')
