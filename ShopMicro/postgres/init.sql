CREATE TABLE IF NOT EXISTS products (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  price NUMERIC(10,2) NOT NULL
);

INSERT INTO products (name, price) VALUES
('Mechanical Keyboard', 79.99),
('4K Monitor', 299.99),
('USB-C Dock', 129.99)
ON CONFLICT DO NOTHING;
