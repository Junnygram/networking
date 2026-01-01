const express = require('express');
const cors = require('cors');
const { createClient } = require('redis');
const { v4: uuidv4 } = require('uuid');

const app = express();
app.use(express.json());
app.use(cors());

const PORT = 3000;
// The 'network-db' hostname is used because that's the service name in docker-compose.
const REDIS_URL = 'redis://network-db:6379';

// --- Redis Client Setup ---
const redisClient = createClient({
  url: REDIS_URL
});

redisClient.on('error', (err) => console.log('Redis Client Error', err));
redisClient.connect();

const NODES_KEY = 'nodes';

// --- API Endpoints ---

// GET /nodes - Get all nodes
app.get('/nodes', async (req, res) => {
  try {
    const nodes = await redisClient.hGetAll(NODES_KEY);
    // hGetAll returns an object, convert it to an array of objects
    const nodesArray = Object.keys(nodes).map(id => JSON.parse(nodes[id]));
    res.json(nodesArray);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// POST /nodes - Create a new node
app.post('/nodes', async (req, res) => {
  try {
    const { name, type = 'service' } = req.body;
    if (!name) {
      return res.status(400).json({ error: 'Node name is required' });
    }
    const newNode = {
      id: uuidv4(),
      name,
      type,
      status: 'online',
      createdAt: new Date().toISOString()
    };
    await redisClient.hSet(NODES_KEY, newNode.id, JSON.stringify(newNode));
    res.status(201).json(newNode);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// PUT /nodes/:id - Update a node
app.put('/nodes/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { name, type, status } = req.body;
    
    const existingNodeStr = await redisClient.hGet(NODES_KEY, id);
    if (!existingNodeStr) {
      return res.status(404).json({ error: 'Node not found' });
    }
    
    const existingNode = JSON.parse(existingNodeStr);
    const updatedNode = {
      ...existingNode,
      name: name || existingNode.name,
      type: type || existingNode.type,
      status: status || existingNode.status
    };

    await redisClient.hSet(NODES_KEY, id, JSON.stringify(updatedNode));
    res.json(updatedNode);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// DELETE /nodes/:id - Delete a node
app.delete('/nodes/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const result = await redisClient.hDel(NODES_KEY, id);
    if (result === 0) {
      return res.status(404).json({ error: 'Node not found' });
    }
    res.status(204).send(); // No Content
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});


app.listen(PORT, () => {
  console.log(`Network API service listening on port ${PORT}`);
});
