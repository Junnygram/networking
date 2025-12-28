# Bonus 2: Distributed Tracing with Jaeger & OpenTelemetry

This directory contains a simple setup to demonstrate distributed tracing. It uses a Python Flask application instrumented with **OpenTelemetry** to send traces to a **Jaeger** backend.

## Components

1.  **`docker-compose.yml`**: Defines two services:
    - `app`: Our simple Python Flask application.
    - `jaeger`: The Jaeger "all-in-one" image, which includes the collector, query UI, and agent.

2.  **`app.py`**: A minimal Flask app with two endpoints (`/` and `/trace`). It is instrumented with the OpenTelemetry SDK. All requests to this app will automatically generate traces and send them to the Jaeger collector.

3.  **`requirements.txt`**: A list of the Python packages required for the `app` service, including Flask and the various OpenTelemetry libraries.

## How to Run

1.  **Start the services:**
    ```bash
    docker-compose up --build -d
    ```

2.  **Generate some traces:**
    Send a few requests to the Flask application.

    ```bash
    curl http://localhost:5000/
    curl http://localhost:5000/trace
    curl http://localhost:5000/
    ```

3.  **View the traces in Jaeger:**
    - Open your web browser and go to `http://localhost:16686`. This is the Jaeger Query UI.
    - In the "Service" dropdown on the left, you should see `my-flask-app`.
    - Click the "Find Traces" button, and you will see the traces for the requests you just made.
    - Click on a trace to see the detailed span view, showing the duration of different operations within the request.

## Key Concepts Demonstrated

- **Code Instrumentation:** The application code is "instrumented" with the OpenTelemetry SDK, which captures execution context and timings.
- **Trace Propagation:** OpenTelemetry automatically creates and propagates trace contexts across network requests (if we were calling other services).
- **Trace Collection:** The Jaeger service acts as a collector for the trace data sent by the application.
- **Trace Visualization:** The Jaeger UI provides a powerful way to search for and visualize the entire lifecycle of a request, making it invaluable for debugging distributed systems.
