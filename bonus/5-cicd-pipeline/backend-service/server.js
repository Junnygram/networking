const express = require('express');
const app = express();
const PORT = 3000;

app.get('/', (req, res) => {
  res.json({ message: 'Hello from the backend service!', timestamp: new Date().toISOString() });
});

app.listen(PORT, () => {
  console.log(`Backend service listening on port ${PORT}`);
});
