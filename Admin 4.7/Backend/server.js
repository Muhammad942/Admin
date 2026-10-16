import 'dotenv/config'; // Must be at the very top line!
import express from 'express';
import feedRouter from './routes/feedRouter.js';
import profileRoutes from './routes/profileRoutes.js';
import { createServer } from 'http';
import { setupChatSocket } from './services/sockets/chatSocket.js';

const app = express();
const server = createServer(app); // 1. Create HTTP server

setupChatSocket(server); // 2. Attach Socket.IO to HTTP server

app.use(express.json());

// Mount feedRouter at /api/feed
app.use('/api/feed', feedRouter);
app.use('/api',profileRoutes);


// Start everything on the same port
server.listen(3000, () => {
  console.log('🚀 Campus API + WebSocket server running on port 3000');
});
