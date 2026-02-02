import { createMiddleware } from 'hono/factory';
import * as jose from 'jose';
import { config } from '../config';

export type AuthContext = {
  Variables: {
    userId: string;
  };
};

export const authMiddleware = createMiddleware<AuthContext>(async (c, next) => {
  const authHeader = c.req.header('Authorization');

  if (!authHeader?.startsWith('Bearer ')) {
    return c.json({ error: 'Missing authorization header' }, 401);
  }

  const token = authHeader.slice(7);

  try {
    const secret = new TextEncoder().encode(config.jwtSecret);
    const { payload } = await jose.jwtVerify(token, secret);

    if (!payload.sub) {
      return c.json({ error: 'Invalid token' }, 401);
    }

    c.set('userId', payload.sub);
    await next();
  } catch {
    return c.json({ error: 'Invalid or expired token' }, 401);
  }
});
