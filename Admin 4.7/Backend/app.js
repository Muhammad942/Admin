import express from 'express';
import cors from 'cors';
import feedRouter from './routes/feedRouter.js';

// Uncomment in production
// import { refreshGeneralNewsFeed } from './services/generalFeedService.js';


const app = express();

// Global Middleware
app.use(cors());
app.use(express.json());

// Mount Routes
app.use('/api/feed', feedRouter);

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'OK', timestamp: new Date() });
});

// TODO: Uncomment in production
//refreshGeneralNewsFeed();
export default app;