import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { logger } from 'hono/logger';
import { authRoutes } from './routes/auth';
import { chatRoutes } from './routes/chat';
import { authMiddleware } from './middleware/auth';
import { apiKeyMiddleware } from './middleware/apiKey';
import { standardRateLimit, authRateLimit, claudeRateLimit } from './middleware/rateLimit';
import { logError } from './services/logger';
import { config } from './config';
import { ValidationError } from './validation/schemas';
import { checkDbHealth } from './db/schema';

const app = new Hono();

// Global error handler
app.onError((err, c) => {
  // Handle validation errors with 400 status
  if (err instanceof ValidationError) {
    return c.json({ error: err.message }, 400);
  }

  logError('server', err);

  // In development, include error details for debugging
  const errorMessage = !config.isProduction && err instanceof Error
    ? `${err.name}: ${err.message}`
    : 'Internal server error';

  return c.json({ error: errorMessage }, 500);
});

// Global middleware
app.use('*', logger());

// CORS configuration
if (config.corsOrigins.length > 0) {
  // Production: restrict to configured origins
  app.use('*', cors({
    origin: config.corsOrigins,
    allowMethods: ['GET', 'POST', 'DELETE', 'OPTIONS'],
    allowHeaders: ['Content-Type', 'Authorization', 'X-API-Key'],
    credentials: true,
  }));
} else if (config.isProduction) {
  // Production without configured origins: deny cross-origin
  app.use('*', cors({
    origin: () => null, // Reject all cross-origin requests
  }));
} else {
  // Development: allow all origins
  app.use('*', cors());
}

app.use('*', apiKeyMiddleware); // API key check - gates all requests

// Health check (allowed without API key for monitoring)
app.get('/health', (c) => {
  const dbHealth = checkDbHealth();
  if (!dbHealth.ok) {
    return c.json({ status: 'unhealthy', db: dbHealth.error }, 503);
  }
  return c.json({ status: 'ok' });
});

// Auth routes with rate limiting (prevent brute force)
app.use('/auth/*', authRateLimit);
app.route('/auth', authRoutes);

// Protected routes with auth middleware
app.use('/chat/*', authMiddleware);

// Apply rate limiting to chat routes
// Standard rate limit for read operations
app.use('/chat', standardRateLimit);
// Claude rate limit for expensive operations (streaming)
app.use('/chat/stream', claudeRateLimit);
app.use('/chat/:id/stream', claudeRateLimit);

app.route('/chat', chatRoutes);

export { app };
