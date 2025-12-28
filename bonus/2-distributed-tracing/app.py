from flask import Flask
import time

# Import OpenTelemetry API
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.resources import Resource

# Import the OTLP (OpenTelemetry Protocol) exporter
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter


# --- OpenTelemetry Setup ---

# Set a resource to identify our service
resource = Resource(attributes={
    "service.name": "my-flask-app"
})

# Create a TracerProvider
provider = TracerProvider(resource=resource)

# Create an OTLP exporter, which will send traces to the Jaeger collector
exporter = OTLPSpanExporter()

# Create a BatchSpanProcessor and add the exporter to it
processor = BatchSpanProcessor(exporter)
provider.add_span_processor(processor)

# Set the TracerProvider as the global provider
trace.set_tracer_provider(provider)

# Get a tracer for the current module
tracer = trace.get_tracer(__name__)


# --- Flask Application ---

app = Flask(__name__)

@app.route('/')
def index():
    # Every request to this endpoint will create a trace
    with tracer.start_as_current_span("index-request") as span:
        span.set_attribute("http.method", "GET")
        span.set_attribute("http.route", "/")
        return "Hello, World!"

@app.route('/trace')
def trace_route():
    # This endpoint demonstrates creating a child span to trace a specific operation
    with tracer.start_as_current_span("trace-request") as parent_span:
        parent_span.set_attribute("http.method", "GET")
        parent_span.set_attribute("http.route", "/trace")

        # Create a child span to trace a "database call"
        with tracer.start_as_current_span("do_work") as child_span:
            child_span.set_attribute("custom.message", "Doing some work...")
            # Simulate some work
            time.sleep(0.1)
            child_span.add_event("Work complete!")

        return "This request has been traced!"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
