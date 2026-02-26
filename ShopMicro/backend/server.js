// Backend Service v1.0 - Capstone Demo
const express = require("express");
const { Pool } = require("pg");
const redis = require("redis");
const client = require("prom-client");

const app = express();
app.use(express.json());

// Initialize Prometheus metrics
const collectDefaultMetrics = client.collectDefaultMetrics;
collectDefaultMetrics();

const httpRequestDurationMicroseconds = new client.Histogram({
  name: "http_request_duration_ms",
  help: "Duration of HTTP requests in ms",
  labelNames: ["method", "route", "code"],
  buckets: [50, 100, 200, 300, 400, 500, 750, 1000, 2000] // defined in milliseconds
});

const httpRequestsTotal = new client.Counter({
  name: "http_requests_total",
  help: "Total number of HTTP requests",
  labelNames: ["method", "route", "code"]
});

// Middleware to capture metrics
app.use((req, res, next) => {
  res.locals.startEpoch = Date.now();
  res.on("finish", () => {
    const responseTimeInMs = Date.now() - res.locals.startEpoch;
    httpRequestDurationMicroseconds
      .labels(req.method, req.route ? req.route.path : req.path, res.statusCode)
      .observe(responseTimeInMs);
    httpRequestsTotal
      .labels(req.method, req.route ? req.route.path : req.path, res.statusCode)
      .inc();
  });
  next();
});

const pool = new Pool({
  host: process.env.DB_HOST || "postgres",
  user: process.env.DB_USER || "postgres",
  password: process.env.DB_PASSWORD || "postgres",
  database: process.env.DB_NAME || "shopmicro",
  port: Number(process.env.DB_PORT || 5432),
});

const cache = redis.createClient({
  url: process.env.REDIS_URL || "redis://redis:6379",
});
cache.connect().catch(console.error);

app.get("/health", async (_req, res) => {
  res.json({ status: "ok", service: "backend" });
});

app.get("/products", async (_req, res) => {
  try {
    const cached = await cache.get("products");
    if (cached) return res.json(JSON.parse(cached));
    const result = await pool.query("SELECT id, name, price FROM products ORDER BY id");
    await cache.setEx("products", 30, JSON.stringify(result.rows));
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: "backend_error", detail: err.message });
  }
});

// Expose metrics endpoint
app.get("/metrics", async (req, res) => {
  res.set("Content-Type", client.register.contentType);
  res.end(await client.register.metrics());
});

app.listen(8080, () => console.log("backend listening on 8080"));
