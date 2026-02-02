import type { Context, Next } from 'hono';
import { config } from '../config';
import { logInfo } from '../services/logger';

/**
 * API Key middleware - gates access to the entire API
 *
 * Requires X-API-Key header with the correct pre-shared secret.
 * This runs BEFORE authentication and rate limiting.
 */
export async function apiKeyMiddleware(c: Context, next: Next) {
  // Skip for health check endpoint
  if (c.req.path === '/health') {
    return next();
  }

  const apiKey = c.req.header('X-API-Key');

  if (!config.apiKey) {
    if (config.isProduction) {
      // In production, reject all requests if API key not configured
      return c.json({ error: 'Server misconfigured: API key required' }, 500);
    }
    // In development, log warning but allow
    console.warn('WARNING: No API_KEY configured. API is open to all requests.');
    return next();
  }

  if (!apiKey) {
    return c.json({ error: 'Missing API key' }, 401);
  }

  // Constant-time comparison to prevent timing attacks
  if (!secureCompare(apiKey, config.apiKey)) {
    logInfo('api-key', `Invalid API key attempt from ${c.req.header('x-forwarded-for') || 'unknown'}`);
    return c.json({ error: 'Invalid API key' }, 401);
  }

  await next();
}

/**
 * Constant-time string comparison to prevent timing attacks
 */
function secureCompare(a: string, b: string): boolean {
  if (a.length !== b.length) {
    return false;
  }

  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }

  return result === 0;
}
