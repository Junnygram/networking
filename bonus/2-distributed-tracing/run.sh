#!/bin/bash

# A script to manage the distributed tracing demo on a fresh Ubuntu server.

set -e # Exit immediately if a command exits with a non-zero status.

# --- Helper functions to generate configuration files ---

generate_docker_compose_yml() {
cat <<EOF
version: '3.7'
services:
  app:
    build: 
      context: .
      dockerfile: Dockerfile
    ports:
      - "5000:5000"
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=jaeger:4317
      - OTEL_EXPORTER_OTLP_INSECURE=true
      - OTEL_SERVICE_NAME=my-flask-app

  jaeger:
    image: jaegertracing/all-in-one:latest
    ports:
      - "16686:16686"
      - "4317:4317"
EOF
}

generate_app_py() {
cat <<EOF
from flask import Flask
import time

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

resource = Resource(attributes={
    "service.name": "my-flask-app"
})
provider = TracerProvider(resource=resource)
exporter = OTLPSpanExporter()
processor = BatchSpanProcessor(exporter)
provider.add_span_processor(processor)
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

app = Flask(__name__)

@app.route('/')
def index():
    with tracer.start_as_current_span("index-request") as span:
        span.set_attribute("http.method", "GET")
        span.set_attribute("http.route", "/")
        return "Hello, World!"

@app.route('/trace')
def trace_route():
    with tracer.start_as_current_span("trace-request") as parent_span:
        parent_span.set_attribute("http.method", "GET")
        parent_span.set_attribute("http.route", "/trace")
        with tracer.start_as_current_span("do_work") as child_span:
            child_span.set_attribute("custom.message", "Doing some work...")
            time.sleep(0.1)
            child_span.add_event("Work complete!")
        return "This request has been traced!"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF
}

generate_requirements_txt() {
cat <<EOF
flask
opentelemetry-api
opentelemetry-sdk
opentelemetry-exporter-otlp-proto-grpc
EOF
}

generate_dockerfile() {
cat <<EOF
FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN apt-get update && apt-get install -y iputils-ping
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
CMD ["python", "app.py"]
EOF
}

# --- Functions ---

check_deps() {
    if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
        echo "Error: Docker or Docker Compose not found."
        echo "Please run './run.sh install' first."
        exit 1
    fi
}

install_deps() {
    echo "--- Updating package list and installing dependencies ---"
    sudo apt-get update -y
    sudo apt-get install -y curl

    echo "--- Installing Docker ---"
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker $USER
        echo "Docker installed. Please log out and log back in for group changes to take effect, or run 'newgrp docker'."
    else
        echo "Docker is already installed."
    fi

    echo "--- Installing Docker Compose ---"
    if ! command -v docker-compose &> /dev/null; then
        COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
        sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        echo "Docker Compose ${COMPOSE_VERSION} installed."
    else
        echo "Docker Compose is already installed."
    fi
    
    echo "--- Installation complete! ---"
    echo "IMPORTANT: You may need to log out and log back in to use 'docker' without 'sudo'."
}

start_services() {
    check_deps
    echo "--- Generating config files ---"
    generate_docker_compose_yml > docker-compose.yml
    generate_app_py > app.py
    generate_requirements_txt > requirements.txt
    generate_dockerfile > Dockerfile
    echo "--- Starting services ---"
    docker-compose up --build -d
    echo "Services are running. View traces at http://localhost:16686"
}

stop_services() {
    check_deps
    echo "--- Stopping services ---"
    docker-compose down -v
    echo "--- Cleaning up generated files ---"
    rm -f docker-compose.yml app.py requirements.txt Dockerfile
    echo "Cleanup complete."
}

test_connection() {
    check_deps
    echo "--- Generating traces ---"
    curl http://localhost:5000/
    curl http://localhost:5000/trace
    curl http://localhost:5000/
    echo "Traces sent. View them in Jaeger at http://localhost:16686"
}

show_help() {
    echo "Usage: ./run.sh [command]"
    echo
    echo "Commands:"
    echo "  install   Install Docker and Docker Compose."
    echo "  up        Generate files and start the services (default action)."
    echo "  down      Stop services and clean up generated files."
    echo "  test      Generate sample traces by sending requests."
    echo "  help      Show this help message."
}

# --- Main Logic ---

CMD=${1:-up}

case "$CMD" in
    install) install_deps ;; 
    up) start_services ;; 
    down) stop_services ;; 
    test) test_connection ;; 
    help) show_help ;; 
    *) echo "Error: Unknown command: $CMD"; show_help; exit 1 ;; 
esac
