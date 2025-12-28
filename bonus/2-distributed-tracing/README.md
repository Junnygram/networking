# Bonus 2: Distributed Tracing with Jaeger & OpenTelemetry

This directory contains a simple setup to demonstrate distributed tracing. It uses a Python Flask application instrumented with **OpenTelemetry** to send traces to a **Jaeger** backend.

## Components

1.  **`run.sh`**: The main script that manages the entire demo. It dynamically generates the `Dockerfile`, `docker-compose.yml`, `app.py`, and `requirements.txt` files.

## How to Run (with `run.sh` script)

This directory includes a convenient script, `run.sh`, to automate setup and execution.

First, make the script executable:
```bash
chmod +x run.sh
```

### 1. Install Dependencies (First time on a new server)
This command will install Docker and Docker Compose if they are not present.
```bash
./run.sh install
```

### 2. Start the Services
This command will generate all necessary files, build the application image, and start the `app` and `jaeger` services.
```bash
./run.sh up
```

### 3. Generate and View Traces
To generate traces, run the `test` command. You can run this multiple times.
```bash
./run.sh test
```
- After generating traces, open your web browser and go to `http://localhost:16686` to view them in the Jaeger UI.
- In the "Service" dropdown, select `my-flask-app` and click "Find Traces".

### 4. Stop the Services
This will stop the services and remove all generated files.
```bash
./run.sh down
```

## Key Concepts Demonstrated

- **Code Instrumentation:** The application code is "instrumented" with the OpenTelemetry SDK, which captures execution context and timings.
- **Trace Propagation:** OpenTelemetry automatically creates and propagates trace contexts across network requests (if we were calling other services).
- **Trace Collection:** The Jaeger service acts as a collector for the trace data sent by the application.
- **Trace Visualization:** The Jaeger UI provides a powerful way to search for and visualize the entire lifecycle of a request, making it invaluable for debugging distributed systems.
