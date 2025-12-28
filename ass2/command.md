# Assignment 2: Manual Service Deployment Commands

This document provides the step-by-step commands to manually deploy the application services into the network created in Assignment 1. This is an alternative to running the `assignment2.sh` script.

**Prerequisites:**
* The network from Assignment 1 must be running.
* You have installed the necessary system packages: `nginx`, `redis-server`, `python3-pip`, `python3-venv`, `postgresql`.
* You have configured PostgreSQL to accept network connections and created the `orders` database.

---

## 1. Create a Python Virtual Environment

It is a best practice to install Python packages in a virtual environment.

```bash
# Create the virtual environment
python3 -m venv networking_venv

# Activate it (optional, as we will call the python executable directly)
# source networking_venv/bin/activate

# Install required packages
networking_venv/bin/python -m pip install Flask requests psycopg2-binary redis
```

## 2. Create Application Source Files

Create the following files in your working directory.

### `nginx.conf`
```bash
cat << 'EOF' > nginx.conf
events { worker_connections 1024; }
http {
    upstream api_gateway { server 10.0.0.20:3000; }
    server {
        listen 80;
        server_name localhost;
        location / {
            proxy_pass http://api_gateway;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF
```

### `api-gateway.py`
```bash
cat << 'EOF' > api-gateway.py
from flask import Flask, jsonify, request
import requests, os
app = Flask(__name__)
PRODUCT_SERVICE = os.getenv("PRODUCT_SERVICE_URL", "http://10.0.0.30:5000")
ORDER_SERVICE = os.getenv("ORDER_SERVICE_URL", "http://10.0.0.40:5000")
@app.route('/health')
def health(): return jsonify({"status": "healthy", "service": "api-gateway"})
@app.route('/api/products', methods=['GET'])
def get_products():
    try:
        res = requests.get(f"{PRODUCT_SERVICE}/products")
        res.raise_for_status()
        return jsonify(res.json()), res.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": "Product service is unavailable", "details": str(e)}), 503
@app.route('/api/orders', methods=['POST'])
def create_order():
    try:
        res = requests.post(f"{ORDER_SERVICE}/orders", json=request.json)
        res.raise_for_status()
        return jsonify(res.json()), res.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": "Order service is unavailable", "details": str(e)}), 503
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000, debug=False)
EOF
```

### `product-service.py`
```bash
cat << 'EOF' > product-service.py
from flask import Flask, jsonify
import redis, json, os, time, sys
app = Flask(__name__)
REDIS_HOST = os.getenv("REDIS_HOST", "10.0.0.50")
cache = redis.Redis(host=REDIS_HOST, port=6379, decode_responses=True, socket_connect_timeout=2)
PRODUCTS = {
    "1": {"id": "1", "name": "Laptop", "price": 999.99},
    "2": {"id": "2", "name": "Mouse", "price": 29.99},
}
def wait_for_redis():
    retries = 30
    print("--- Checking for Redis connectivity ---", file=sys.stderr)
    while retries > 0:
        try:
            cache.ping()
            print("✅ Successfully connected to Redis.", file=sys.stderr)
            return True
        except redis.exceptions.ConnectionError:
            print(f"Waiting for Redis... ({retries} retries left)", file=sys.stderr)
            retries -= 1
            time.sleep(2)
    print("❌ Could not connect to Redis. Exiting.", file=sys.stderr)
    return False
@app.route('/health')
def health():
    try:
        cache.ping()
        return jsonify({"status": "healthy", "cache": "connected"})
    except redis.exceptions.ConnectionError:
        return jsonify({"status": "unhealthy", "cache": "disconnected"}), 503
@app.route('/products', methods=['GET'])
def get_products(): return jsonify(list(PRODUCTS.values()))
@app.route('/products/<product_id>', methods=['GET'])
def get_product(product_id):
    prod = PRODUCTS.get(product_id)
    return jsonify(prod) if prod else (jsonify({"error": "Not found"}), 404)
if __name__ == '__main__':
    if wait_for_redis():
        app.run(host='0.0.0.0', port=5000, debug=False)
    else:
        sys.exit(1)
EOF
```

### `order-service.py`
```bash
cat << 'EOF' > order-service.py
from flask import Flask, jsonify, request
import psycopg2, os, sys
app = Flask(__name__)
DB_HOST = os.getenv("DB_HOST", "10.0.0.1")
def get_db():
    return psycopg2.connect(host=DB_HOST, dbname="orders", user="postgres", password="postgres")
def init_db():
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute('CREATE TABLE IF NOT EXISTS orders (id SERIAL PRIMARY KEY, customer_id TEXT, total_price REAL);')
        conn.commit()
    except psycopg2.OperationalError as e:
        print(f"Could not connect to database: {e}", file=sys.stderr)
        sys.exit(1)
@app.route('/health')
def health():
    try:
        get_db().close()
        return jsonify({"status": "healthy", "database": "connected"})
    except psycopg2.OperationalError:
        return jsonify({"status": "unhealthy", "database": "disconnected"}), 503
@app.route('/orders', methods=['POST'])
def create_order():
    data = request.json
    conn = get_db()
    cur = conn.cursor()
    cur.execute('INSERT INTO orders (customer_id, total_price) VALUES (%s, %s) RETURNING id', (data['customer_id'], data['total_price']))
    order_id = cur.fetchone()[0]
    conn.commit()
    return jsonify({"order_id": order_id}), 201
if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF
```

## 3. Start the Services

Run each service inside its designated namespace. It's recommended to run each command in a separate terminal window to see its log output.

### Start Redis
```bash
sudo ip netns exec redis-cache redis-server --bind 0.0.0.0 --port 6379 --daemonize yes --protected-mode no
```

### Start Product Service
```bash
sudo ip netns exec product-service networking_venv/bin/python product-service.py
```

### Start Order Service
```bash
sudo ip netns exec order-service networking_venv/bin/python order-service.py
```

### Start API Gateway
```bash
sudo ip netns exec api-gateway networking_venv/bin/python api-gateway.py
```

### Start Nginx
```bash
# Create a temporary directory for the config and copy it
sudo mkdir -p /tmp/nginx
sudo cp nginx.conf /tmp/nginx/nginx.conf

# Start Nginx
sudo ip netns exec nginx-lb nginx -c /tmp/nginx/nginx.conf
```

## 4. Verification

You can test the services from within the namespaces.

**Test API Gateway health:**
```bash
sudo ip netns exec api-gateway curl http://127.0.0.1:3000/health
```

**Test the full flow through Nginx:**
```bash
sudo ip netns exec nginx-lb curl http://10.0.0.20:3000/api/products
```

## 5. Cleanup

To stop the services, you will need to find and kill the processes.

```bash
# Stop Python and Nginx processes by name
sudo pkill -f "api-gateway.py"
sudo pkill -f "product-service.py"
sudo pkill -f "order-service.py"
sudo pkill -f "nginx"

# Stop the Redis server
sudo pkill -f "redis-server"
```
You can then remove the generated files.
