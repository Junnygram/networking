import { useEffect, useState } from "react";

const API_BASE = import.meta.env.VITE_API_BASE || "http://localhost:8080";
const ML_BASE = import.meta.env.VITE_ML_BASE || "http://localhost:5000";

export default function App() {
  const [products, setProducts] = useState([]);
  const [recs, setRecs] = useState([]);

  useEffect(() => {
    fetch(`${API_BASE}/products`).then(r => r.json()).then(setProducts).catch(() => setProducts([]));
    fetch(`${ML_BASE}/recommendations/42`).then(r => r.json()).then(d => setRecs(d.recommendations || [])).catch(() => setRecs([]));
  }, []);

  return (
    <main style={{ fontFamily: "sans-serif", maxWidth: 720, margin: "2rem auto" }}>
      <h1>ShopMicro</h1>
      <h2>Products</h2>
      <ul>{products.map(p => <li key={p.id}>{p.name} - ${p.price}</li>)}</ul>
      <h2>Recommended for User 42</h2>
      <ul>{recs.map(r => <li key={r}>{r}</li>)}</ul>
    </main>
  );
}
