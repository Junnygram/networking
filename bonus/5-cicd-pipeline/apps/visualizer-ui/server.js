const express = require('express');
const path = require('path');
const fetch = require('node-fetch');

const app = express();
const PORT = 8080;
const API_SERVICE_URL = 'http://network-api:3000';

// Serve static files from the 'public' directory
app.use(express.static(path.join(__dirname, 'public')));
app.use(express.json()); // Middleware to parse JSON bodies

// Proxy for all API requests
app.all('/api/*', async (req, res) => {
  try {
    const path = req.path.replace('/api', '');
    const url = `${API_SERVICE_URL}${path}`;
    
    const options = {
      method: req.method,
      headers: {
        'Content-Type': 'application/json'
      }
    };

    if (req.method !== 'GET' && req.method !== 'DELETE') {
      options.body = JSON.stringify(req.body);
    }

    const response = await fetch(url, options);
    
    // If the backend returns no content (like for a DELETE request),
    // send the status code without a body.
    if (response.status === 204) {
      return res.status(204).send();
    }
    
    const data = await response.json();
    res.status(response.status).json(data);

  } catch (error) {
    console.error('API Proxy Error:', error);
    res.status(500).json({ error: 'Failed to communicate with the API service.' });
  }
});

// Fallback to index.html for any other requests (for client-side routing)
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.listen(PORT, () => {
  console.log(`Visualizer UI service listening on port ${PORT}`);
});
