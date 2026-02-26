import time
from flask import Flask, jsonify, request, Response
import random
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)

# Basic metrics
REQUEST_COUNT = Counter('shopmicro_ml_requests_total', 'Total ML requests', ['method', 'endpoint', 'http_status'])
REQUEST_LATENCY = Histogram('shopmicro_ml_request_duration_seconds', 'ML Request latency', ['method', 'endpoint'])

@app.before_request
def before_request():
    request.start_time = time.time()

@app.after_request
def after_request(response):
    req_time = time.time() - request.start_time
    REQUEST_LATENCY.labels(request.method, request.path).observe(req_time)
    REQUEST_COUNT.labels(request.method, request.path, response.status_code).inc()
    return response

@app.get("/health")
def health():
    return jsonify({"status": "ok", "service": "ml-service"})

@app.get("/recommendations/<int:user_id>")
def recommendations(user_id: int):
    catalog = ["keyboard", "monitor", "headset", "mouse", "webcam"]
    random.seed(user_id)
    picks = random.sample(catalog, 3)
    return jsonify({"user_id": user_id, "recommendations": picks})

@app.get("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
