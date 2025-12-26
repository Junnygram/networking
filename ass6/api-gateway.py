from flask import Flask, jsonify, request
import requests
import os

app = Flask(__name__)

# Service discovery: Docker Swarm will resolve these service names to the correct container IPs.
PRODUCT_SERVICE_URL = "http://product-service:5000"
ORDER_SERVICE_URL = "http://order-service:5000"

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "service": "api-gateway"})

@app.route('/api/products', methods=['GET'])
def get_products():
    try:
        response = requests.get(f"{PRODUCT_SERVICE_URL}/products")
        response.raise_for_status()  # Raise an exception for bad status codes
        return jsonify(response.json()), response.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Product service unavailable: {str(e)}"}), 503

@app.route('/api/products/<id>', methods=['GET'])
def get_product(id):
    try:
        response = requests.get(f"{PRODUCT_SERVICE_URL}/products/{id}")
        response.raise_for_status()
        return jsonify(response.json()), response.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Product service unavailable: {str(e)}"}), 503

@app.route('/api/orders', methods=['POST'])
def create_order():
    try:
        response = requests.post(f"{ORDER_SERVICE_URL}/orders", json=request.json)
        response.raise_for_status()
        return jsonify(response.json()), response.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Order service unavailable: {str(e)}"}), 503

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000)
