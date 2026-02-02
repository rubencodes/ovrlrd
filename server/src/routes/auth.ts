import { Hono } from 'hono';
import * as jose from 'jose';
import { config } from '../config';
import { createUser, getUserByAppleId, updateDeviceToken } from '../db/users';
import { logError, logInfo } from '../services/logger';
import { logAuditEvent, AuditActions } from '../services/audit';
import { authRequestSchema, parseBody } from '../validation/schemas';
import { getClientIp, getUserAgent } from '../utils/request';

const auth = new Hono();

// Apple's public key URL for Sign In with Apple
const APPLE_KEYS_URL = 'https://appleid.apple.com/auth/keys';

// Token expiration constants
const TOKEN_EXPIRY_HOURS = 24;
const TOKEN_REFRESH_GRACE_HOURS = 4;

interface AppleTokenPayload {
  iss: string;
  aud: string;
  exp: number;
  iat: number;
  sub: string; // Apple user ID
  email?: string;
  email_verified?: boolean;
}

async function verifyAppleToken(identityToken: string): Promise<AppleTokenPayload> {
  const JWKS = jose.createRemoteJWKSet(new URL(APPLE_KEYS_URL));

  const { payload } = await jose.jwtVerify(identityToken, JWKS, {
    issuer: 'https://appleid.apple.com',
    audience: config.appleBundleId,
  });

  return payload as unknown as AppleTokenPayload;
}

interface TokenPayload extends jose.JWTPayload {
  sub: string;       // User ID
  deviceId?: string; // Device binding
}

async function createSessionToken(userId: string, deviceId?: string): Promise<string> {
  const secret = new TextEncoder().encode(config.jwtSecret);

  const payload: TokenPayload = { sub: userId };
  if (deviceId) {
    payload.deviceId = deviceId;
  }

  return await new jose.SignJWT(payload)
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime(`${TOKEN_EXPIRY_HOURS}h`)
    .sign(secret);
}

auth.post('/', async (c) => {
  const ip = getClientIp(c);
  const userAgent = getUserAgent(c);

  try {
    const { identityToken, deviceToken, deviceId } = await parseBody(
      c.req.raw,
      authRequestSchema
    );

    // Verify Apple identity token
    const applePayload = await verifyAppleToken(identityToken);
    const appleUserId = applePayload.sub;
    const email = applePayload.email?.toLowerCase();

    logInfo('auth', `Auth attempt: appleUserId=${appleUserId}, email=${email || 'none'}`);

    // Find existing user first
    let user = await getUserByAppleId(appleUserId);

    if (!user) {
      // New user - check if approved by email or Apple ID
      const isApprovedByEmail = email && config.approvedEmails.includes(email);
      const isApprovedByAppleId = config.approvedAppleIds.includes(appleUserId);

      if (config.approvedEmails.length > 0 || config.approvedAppleIds.length > 0) {
        if (!isApprovedByEmail && !isApprovedByAppleId) {
          logInfo('auth', `Rejected unapproved new user: email=${email || 'none'}, appleId=${appleUserId}`);
          return c.json({ error: 'User not authorized' }, 403);
        }
      }

      // Create new user
      user = await createUser({
        appleUserId,
        email: applePayload.email,
      });
      logInfo('auth', `Created new user: ${user.id} (${email})`);
    } else {
      // Existing user - already approved, let them in
      logInfo('auth', `Returning user: ${user.id}`);
    }

    // Update device token if provided
    if (deviceToken) {
      await updateDeviceToken(user.id, deviceToken);
    }

    // Create session token with device binding
    const sessionToken = await createSessionToken(user.id, deviceId);

    // Audit log
    logAuditEvent({
      userId: user.id,
      action: AuditActions.AUTH_LOGIN,
      resource: 'session',
      metadata: { deviceId, hasDeviceToken: !!deviceToken },
      ip,
      userAgent,
    });

    logInfo('auth', 'User authenticated', { userId: user.id });

    return c.json({
      sessionToken,
      userId: user.id,
      expiresIn: TOKEN_EXPIRY_HOURS * 60 * 60, // seconds
    });
  } catch (error) {
    logError('auth', error);
    return c.json({ error: 'Authentication failed' }, 401);
  }
});

// Token refresh endpoint
auth.post('/refresh', async (c) => {
  const authHeader = c.req.header('Authorization');
  const ip = getClientIp(c);
  const userAgent = getUserAgent(c);

  if (!authHeader?.startsWith('Bearer ')) {
    return c.json({ error: 'Missing authorization header' }, 401);
  }

  const token = authHeader.slice(7);

  try {
    const secret = new TextEncoder().encode(config.jwtSecret);

    // Verify but allow expired tokens for refresh (within grace period)
    const { payload } = await jose.jwtVerify(token, secret, {
      clockTolerance: TOKEN_REFRESH_GRACE_HOURS * 60 * 60,
    });

    if (!payload.sub) {
      return c.json({ error: 'Invalid token' }, 401);
    }

    const deviceId = (payload as TokenPayload).deviceId;

    // Create new token
    const newToken = await createSessionToken(payload.sub, deviceId);

    // Audit log
    logAuditEvent({
      userId: payload.sub,
      action: AuditActions.AUTH_TOKEN_REFRESH,
      resource: 'session',
      metadata: { deviceId },
      ip,
      userAgent,
    });

    return c.json({
      sessionToken: newToken,
      userId: payload.sub,
      expiresIn: TOKEN_EXPIRY_HOURS * 60 * 60,
    });
  } catch {
    return c.json({ error: 'Token refresh failed' }, 401);
  }
});

export { auth as authRoutes };
