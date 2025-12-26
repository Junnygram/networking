from flask import Flask, jsonify
import redis
import json
import os

app = Flask(__name__)

# Connect to Redis using the hostname defined in docker-compose.yml
# The REDIS_HOST environment variable is passed from the compose file.
redis_host = os.environ.get('REDIS_HOST', 'localhost')
cache = redis.Redis(host=redis_host, port=6379, decode_responses=True)

# In-memory product catalog as a fallback
PRODUCTS = {
    "1": {"id": "1", "name": "Cloud Laptop", "price": 1299.99, "stock": 50},
    "2": {"id": "2", "name": "Container Mouse", "price": 39.99, "stock": 200},
    "3": {"id": "3", "name": "Serverless Keyboard", "price": 89.99, "stock": 150},
}

@app.route('/health')
def health():
    # Check Redis connection
    try:
        cache.ping()
        redis_status = "connected"
    except redis.exceptions.ConnectionError:
        redis_status = "disconnected"
    return jsonify({"status": "healthy", "service": "product-service", "redis": redis_status})

@app.route('/products', methods=['GET'])
def get_products():
    try:
        cached_products = cache.get('all_products')
        if cached_products:
            return jsonify(json.loads(cached_products))
    except redis.exceptions.ConnectionError as e:
        # If cache is down, log it but proceed without it
        app.logger.error(f"Redis connection error: {e}")

    # If not in cache or cache is down, get from fallback and try to cache it
    products = list(PRODUCTS.values())
    try:
        cache.setex('all_products', 300, json.dumps(products)) # Cache for 5 minutes
    except redis.exceptions.ConnectionError as e:
        app.logger.error(f"Could not write to Redis: {e}")

    return jsonify(products)

@app.route('/products/<product_id>', methods=['GET'])
def get_product(product_id):
    try:
        cached_product = cache.get(f'product_{product_id}')
        if cached_product:
            return jsonify(json.loads(cached_product))
    except redis.exceptions.ConnectionError as e:
        app.logger.error(f"Redis connection error: {e}")

    product = PRODUCTS.get(product_id)
    if not product:
        return jsonify({"error": "Product not found"}), 404

    try:
        cache.setex(f'product_{product_id}', 300, json.dumps(product))
    except redis.exceptions.ConnectionError as e:
        app.logger.error(f"Could not write to Redis: {e}")

    return jsonify(product)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
