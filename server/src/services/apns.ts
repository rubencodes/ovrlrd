import * as jose from 'jose';
import { config } from '../config';
import { logError, logDebug } from './logger';

interface PushPayload {
  title: string;
  body: string;
  conversationId: string;
  type?: string;
}

// Token cache with mutex to prevent thundering herd
let apnsToken: string | null = null;
let tokenExpiry: number = 0;
let tokenRefreshPromise: Promise<string> | null = null;

/**
 * Get APNs token with mutex to prevent concurrent token generation
 */
async function getApnsToken(): Promise<string> {
  const now = Date.now();

  // Reuse token if not expired (tokens last 1 hour, we refresh at 50 min)
  if (apnsToken && tokenExpiry > now) {
    return apnsToken;
  }

  // If another request is already refreshing, wait for it
  if (tokenRefreshPromise) {
    return tokenRefreshPromise;
  }

  // Start token refresh with mutex
  tokenRefreshPromise = refreshToken();

  try {
    const token = await tokenRefreshPromise;
    return token;
  } finally {
    tokenRefreshPromise = null;
  }
}

/**
 * Actually refresh the token (called only once per refresh cycle)
 */
async function refreshToken(): Promise<string> {
  logDebug('apns', 'Refreshing APNs token');

  // Read the APNs key
  const keyFile = Bun.file(config.apnsKeyPath);

  if (!(await keyFile.exists())) {
    throw new Error(`APNs key file not found: ${config.apnsKeyPath}`);
  }

  const keyContent = await keyFile.text();
  const privateKey = await jose.importPKCS8(keyContent, 'ES256');

  // Create JWT
  const token = await new jose.SignJWT({})
    .setProtectedHeader({
      alg: 'ES256',
      kid: config.apnsKeyId,
    })
    .setIssuer(config.appleTeamId)
    .setIssuedAt()
    .sign(privateKey);

  // Cache the token
  apnsToken = token;
  tokenExpiry = Date.now() + 50 * 60 * 1000; // 50 minutes

  logDebug('apns', 'APNs token refreshed');
  return token;
}

// Fetch timeout for APNs requests (30 seconds)
const APNS_TIMEOUT_MS = 30_000;

// Max retry attempts for transient failures
const MAX_RETRIES = 3;

// Delay between retries (exponential backoff)
function getRetryDelay(attempt: number): number {
  return Math.min(1000 * Math.pow(2, attempt), 10_000); // 1s, 2s, 4s, max 10s
}

export interface PushResult {
  success: boolean;
  error?: string;
}

export async function sendPushNotification(
  deviceToken: string,
  payload: PushPayload
): Promise<PushResult> {
  if (!config.apnsKeyId || !config.appleTeamId) {
    logDebug('apns', 'APNs not configured, skipping push notification');
    return { success: false, error: 'APNs not configured' };
  }

  let lastError: string | undefined;

  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    try {
      const token = await getApnsToken();

      // Use production APNs endpoint
      // For development, use: api.sandbox.push.apple.com
      const isProduction = config.isProduction;
      const host = isProduction ? 'api.push.apple.com' : 'api.sandbox.push.apple.com';
      const url = `https://${host}/3/device/${deviceToken}`;

      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'authorization': `bearer ${token}`,
          'apns-topic': config.appleBundleId,
          'apns-push-type': 'alert',
          'apns-priority': '10',
        },
        body: JSON.stringify({
          aps: {
            alert: {
              title: payload.title,
              body: payload.body,
            },
            sound: 'default',
            'thread-id': payload.conversationId,
          },
          conversationId: payload.conversationId,
          type: payload.type ?? 'message_ready',
        }),
        signal: AbortSignal.timeout(APNS_TIMEOUT_MS),
      });

      if (response.ok) {
        logDebug('apns', 'Push notification sent', { conversationId: payload.conversationId });
        return { success: true };
      }

      const errorText = await response.text();
      lastError = `APNs error ${response.status}: ${errorText}`;

      // Don't retry client errors (4xx), only server errors (5xx)
      if (response.status >= 400 && response.status < 500) {
        logError('apns', new Error(lastError));
        return { success: false, error: lastError };
      }

      // Server error - retry after delay
      logDebug('apns', `APNs server error, retrying (attempt ${attempt + 1}/${MAX_RETRIES})`);
      if (attempt < MAX_RETRIES - 1) {
        await new Promise(resolve => setTimeout(resolve, getRetryDelay(attempt)));
      }
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);

      // Timeout or network error - retry
      if (attempt < MAX_RETRIES - 1) {
        logDebug('apns', `APNs request failed, retrying (attempt ${attempt + 1}/${MAX_RETRIES}): ${lastError}`);
        await new Promise(resolve => setTimeout(resolve, getRetryDelay(attempt)));
      } else {
        logError('apns', error);
      }
    }
  }

  return { success: false, error: lastError };
}
