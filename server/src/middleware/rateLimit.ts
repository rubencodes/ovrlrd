import type { Context, Next } from 'hono';
import { logInfo } from '../services/logger';

interface RateLimitEntry {
  count: number;
  resetAt: number;
}

// In-memory store - for production, use Redis
const rateLimitStore = new Map<string, RateLimitEntry>();

// Clean up expired entries every 5 minutes
// Using unref() allows the process to exit even if this timer is running
const cleanupInterval = setInterval(() => {
  const now = Date.now();
  for (const [key, entry] of rateLimitStore) {
    if (entry.resetAt < now) {
      rateLimitStore.delete(key);
    }
  }
}, 5 * 60 * 1000);

// Allow process to exit without waiting for cleanup interval
if (typeof cleanupInterval.unref === 'function') {
  cleanupInterval.unref();
}

interface RateLimitConfig {
  windowMs: number;      // Time window in milliseconds
  maxRequests: number;   // Max requests per window
  keyGenerator?: (c: Context) => string;  // Custom key generator
}

/**
 * Rate limiting middleware
 *
 * Default: 20 requests per minute per user
 * For Claude endpoints: 10 requests per minute (expensive operations)
 */
export function rateLimit(config: RateLimitConfig) {
  const { windowMs, maxRequests, keyGenerator } = config;

  return async (c: Context, next: Next) => {
    // Generate key - default to userId if available, otherwise IP
    const userId = c.get('userId') as string | undefined;
    const ip = c.req.header('x-forwarded-for') || c.req.header('cf-connecting-ip') || 'unknown';
    const key = keyGenerator ? keyGenerator(c) : (userId || ip);

    const now = Date.now();
    const entry = rateLimitStore.get(key);

    if (!entry || entry.resetAt < now) {
      // New window
      rateLimitStore.set(key, {
        count: 1,
        resetAt: now + windowMs,
      });
    } else if (entry.count >= maxRequests) {
      // Rate limit exceeded
      const retryAfter = Math.ceil((entry.resetAt - now) / 1000);

      logInfo('rate-limit', `Rate limit exceeded for ${key}`);

      c.header('X-RateLimit-Limit', maxRequests.toString());
      c.header('X-RateLimit-Remaining', '0');
      c.header('X-RateLimit-Reset', Math.ceil(entry.resetAt / 1000).toString());
      c.header('Retry-After', retryAfter.toString());

      return c.json(
        { error: 'Too many requests. Please slow down.' },
        429
      );
    } else {
      // Increment counter
      entry.count++;
    }

    // Add rate limit headers to response
    const currentEntry = rateLimitStore.get(key)!;
    c.header('X-RateLimit-Limit', maxRequests.toString());
    c.header('X-RateLimit-Remaining', Math.max(0, maxRequests - currentEntry.count).toString());
    c.header('X-RateLimit-Reset', Math.ceil(currentEntry.resetAt / 1000).toString());

    await next();
  };
}

// Pre-configured rate limiters
export const standardRateLimit = rateLimit({
  windowMs: 60 * 1000,  // 1 minute
  maxRequests: 30,      // 30 requests per minute
});

export const claudeRateLimit = rateLimit({
  windowMs: 60 * 1000,  // 1 minute
  maxRequests: 10,      // 10 Claude requests per minute (expensive!)
});

export const authRateLimit = rateLimit({
  windowMs: 15 * 60 * 1000,  // 15 minutes
  maxRequests: 10,           // 10 auth attempts per 15 minutes
});
