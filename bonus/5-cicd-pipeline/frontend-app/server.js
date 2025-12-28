const express = require('express');
const fetch = require('node-fetch');
const path = require('path');

const app = express();
const PORT = 8080;

// The URL for the backend service, using the name defined in docker-compose.yml
const BACKEND_URL = 'http://backend-service:3000';

// Serve static files from the 'public' directory
app.use(express.static('public'));

app.get('/api/message', async (req, res) => {
  try {
    const response = await fetch(BACKEND_URL);
    const data = await response.json();
    res.json(data);
  } catch (error) {
    console.error('Error fetching from backend:', error);
    res.status(500).json({ error: 'Could not connect to the backend service.' });
  }
});

app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(PORT, () => {
  console.log(`Frontend service listening on port ${PORT}`);
});
