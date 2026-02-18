from flask import Flask, jsonify, request
import random

app = Flask(__name__)

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
    return "shopmicro_ml_requests_total 1\n", 200, {"Content-Type": "text/plain; version=0.0.4"}

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
