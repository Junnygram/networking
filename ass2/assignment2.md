

# 📝 Assignment 2: Microservices Setup in Network Namespaces

---

## **Step 0: Ensure Network Namespaces Are Up**

Make sure your namespaces from Assignment 1 exist and can ping each other.

```bash
ip netns list
# Should show: nginx-lb, api-gateway, product-service, order-service, redis-cache, postgres-db

# Test connectivity
sudo ip netns exec product-service ping -c 2 10.0.0.60   # product-service → postgres-db
sudo ip netns exec redis-cache ping -c 2 10.0.0.10       # redis-cache → nginx-lb
```

Also, make sure DNS works for internet if needed (optional):

```bash
sudo ip netns exec product-service ping -c 2 google.com
```

---

## **Step 1: Deploy Nginx Load Balancer**

1. Create configuration directory inside `nginx-lb` namespace:

```bash
sudo ip netns exec nginx-lb mkdir -p /tmp/nginx
```

2. Create `/tmp/nginx/nginx.conf` with **upstream pointing to API Gateway** (`10.0.0.20:3000`):

```nginx
events {
    worker_connections 1024;
}

http {
    upstream api_gateway {
        server 10.0.0.20:3000;
    }

    server {
        listen 80;

        location / {
            proxy_pass http://api_gateway;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }

        location /health {
            return 200 "OK\n";
            add_header Content-Type text/plain;
        }
    }
}
```

3. Start nginx inside the namespace:

```bash
sudo ip netns exec nginx-lb nginx -c /tmp/nginx/nginx.conf
```

✅ **Test:**

```bash
sudo ip netns exec nginx-lb curl http://10.0.0.10/health
# Should return "OK"
```

> If nginx is complicated to run inside namespace, you can **simulate with Python http.server** and a basic proxy.

---

## **Step 2: API Gateway**

1. Create `api-gateway.py` inside host, then run it in namespace `api-gateway`:

```python
# api-gateway.py
from flask import Flask, jsonify, request
import requests

app = Flask(__name__)

PRODUCT_SERVICE = "http://10.0.0.30:5000"
ORDER_SERVICE = "http://10.0.0.40:5000"

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "service": "api-gateway"})

@app.route('/api/products', methods=['GET'])
def get_products():
    try:
        response = requests.get(f"{PRODUCT_SERVICE}/products")
        return jsonify(response.json()), response.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 503

@app.route('/api/products/<id>', methods=['GET'])
def get_product(id):
    try:
        response = requests.get(f"{PRODUCT_SERVICE}/products/{id}")
        return jsonify(response.json()), response.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 503

@app.route('/api/orders', methods=['POST'])
def create_order():
    try:
        response = requests.post(f"{ORDER_SERVICE}/orders", json=request.json)
        return jsonify(response.json()), response.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 503

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000)
```

2. Run inside namespace:

```bash
sudo ip netns exec api-gateway python3 api-gateway.py &
```

✅ **Test:**

```bash
sudo ip netns exec api-gateway curl http://10.0.0.20/health
# Should return JSON status healthy
```

---

## **Step 3: Product Service**

1. Create `product-service.py`:

```python
from flask import Flask, jsonify
import redis, json

app = Flask(__name__)
cache = redis.Redis(host='10.0.0.50', port=6379, decode_responses=True)

PRODUCTS = {
    "1": {"id": "1", "name": "Laptop", "price": 999.99, "stock": 50},
    "2": {"id": "2", "name": "Mouse", "price": 29.99, "stock": 200},
    "3": {"id": "3", "name": "Keyboard", "price": 79.99, "stock": 150},
}

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "service": "product-service"})

@app.route('/products', methods=['GET'])
def get_products():
    if cache:
        cached = cache.get('all_products')
        if cached:
            return jsonify(json.loads(cached))
    products = list(PRODUCTS.values())
    if cache:
        cache.setex('all_products', 300, json.dumps(products))
    return jsonify(products)

@app.route('/products/<product_id>', methods=['GET'])
def get_product(product_id):
    if cache:
        cached = cache.get(f'product_{product_id}')
        if cached:
            return jsonify(json.loads(cached))
    product = PRODUCTS.get(product_id)
    if not product:
        return jsonify({"error": "Product not found"}), 404
    if cache:
        cache.setex(f'product_{product_id}', 300, json.dumps(product))
    return jsonify(product)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

2. Run inside namespace:

```bash
sudo ip netns exec product-service python3 product-service.py &
```

✅ **Test:**

```bash
sudo ip netns exec product-service curl http://10.0.0.30/products
```

---

## **Step 4: Order Service**

1. Create `order-service.py`:

```python
from flask import Flask, jsonify, request
import psycopg2

app = Flask(__name__)

def get_db():
    return psycopg2.connect(
        host='10.0.0.60', database='orders',
        user='postgres', password='postgres'
    )

def init_db():
    conn = get_db()
    cur = conn.cursor()
    cur.execute('''
        CREATE TABLE IF NOT EXISTS orders (
            id SERIAL PRIMARY KEY,
            customer_id VARCHAR(100),
            product_id VARCHAR(100),
            quantity INTEGER,
            total_price DECIMAL(10, 2),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    conn.commit()
    cur.close()
    conn.close()

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "service": "order-service"})

@app.route('/orders', methods=['POST'])
def create_order():
    data = request.json
    conn = get_db()
    cur = conn.cursor()
    cur.execute(
        '''INSERT INTO orders (customer_id, product_id, quantity, total_price)
           VALUES (%s, %s, %s, %s) RETURNING id''',
        (data['customer_id'], data['product_id'], data['quantity'], data['total_price'])
    )
    order_id = cur.fetchone()[0]
    conn.commit()
    cur.close()
    conn.close()
    return jsonify({"order_id": order_id, "status": "created"}), 201

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000)
```

2. Run inside namespace:

```bash
sudo ip netns exec order-service python3 order-service.py &
```

✅ **Test:**

```bash
sudo ip netns exec order-service curl -X POST http://10.0.0.40/orders \
  -H "Content-Type: application/json" \
  -d '{"customer_id": "1", "product_id": "1", "quantity": 1, "total_price": 999.99}'
```

---

## **Step 5: Deploy Redis and PostgreSQL**

1. Redis:

```bash
sudo ip netns exec redis-cache redis-server --bind 0.0.0.0 &
```

✅ **Test Redis connectivity:**

```bash
sudo ip netns exec product-service redis-cli -h 10.0.0.50 ping
# Should return PONG
```

2. PostgreSQL (simplified, otherwise use Docker):

```bash
sudo ip netns exec postgres-db postgres -D /var/lib/postgresql/data &
```

✅ **Test PostgreSQL connectivity:**

```bash
sudo ip netns exec order-service psql -h 10.0.0.60 -U postgres -d orders -c '\dt'
```

---

## **Step 6: Test Full Flow**

1. Check Product Service through API Gateway:

```bash
sudo ip netns exec nginx-lb curl http://10.0.0.10/api/products
```

2. Create an order:

```bash
sudo ip netns exec nginx-lb curl -X POST http://10.0.0.10/api/orders \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"1","product_id":"1","quantity":1,"total_price":999.99}'
```

✅ **If successful:**

* Nginx LB → API Gateway → Product / Order services → Redis / Postgres

---

