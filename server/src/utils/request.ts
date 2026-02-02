import type { Context } from 'hono';

/**
 * Extract client IP address from request headers
 * Checks common proxy headers in order of preference
 */
export function getClientIp(c: Context): string {
  return (
    c.req.header('x-forwarded-for')?.split(',')[0]?.trim() ||
    c.req.header('cf-connecting-ip') ||
    c.req.header('x-real-ip') ||
    'unknown'
  );
}

/**
 * Extract user agent from request
 */
export function getUserAgent(c: Context): string {
  return c.req.header('user-agent') || 'unknown';
}
