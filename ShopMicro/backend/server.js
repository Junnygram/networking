const express = require("express");
const { Pool } = require("pg");
const redis = require("redis");

const app = express();
app.use(express.json());

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

app.listen(8080, () => console.log("backend listening on 8080"));
