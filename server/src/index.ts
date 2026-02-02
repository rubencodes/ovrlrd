import { app } from './app';
import { config } from './config';
import { initDb } from './db/schema';
import { cancelStream, getActiveSessionCount } from './services/claude-stream';
import { logInfo, logError } from './services/logger';

// Initialize database (runs migrations automatically)
await initDb();

console.log(`Server starting on port ${config.port}`);

// Graceful shutdown handler
async function shutdown(signal: string) {
  logInfo('server', `Received ${signal}, shutting down gracefully...`);

  const activeCount = getActiveSessionCount();
  if (activeCount > 0) {
    logInfo('server', `Cancelling ${activeCount} active Claude session(s)...`);
  }

  // Note: We don't have access to conversation IDs here, so we rely on
  // process exit to clean up. The activeSessions map cleanup happens
  // automatically when processes are killed.

  process.exit(0);
}

// Register signal handlers
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

export default {
  port: config.port,
  fetch: app.fetch,
  idleTimeout: 120, // Allow 2 minutes for SSE/long-running requests
};
