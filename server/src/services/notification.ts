import { sendPushNotification, type PushResult } from './apns';
import { getUserById } from '../db/users';
import { logDebug, logError, logInfo } from './logger';

export interface MessageReadyPayload {
  conversationId: string;
  title?: string;
  messagePreview?: string;
}

/**
 * Send a "message_ready" push notification when a streaming response completes.
 * This notifies the iOS app that a new response is available.
 *
 * Returns immediately without blocking - the notification is sent asynchronously.
 */
export function sendMessageReadyNotification(
  userId: string,
  payload: MessageReadyPayload
): void {
  // Fire and forget - don't block the streaming response
  sendNotificationAsync(userId, payload).catch((error) => {
    logError('notification', `Failed to send notification: ${error}`);
  });
}

async function sendNotificationAsync(
  userId: string,
  payload: MessageReadyPayload
): Promise<PushResult> {
  // Get user's device token
  const user = await getUserById(userId);

  if (!user) {
    logDebug('notification', `User not found: ${userId}`);
    return { success: false, error: 'User not found' };
  }

  if (!user.deviceToken) {
    logDebug('notification', `No device token for user: ${userId}`);
    return { success: false, error: 'No device token' };
  }

  logInfo('notification', `Sending message_ready notification for conversation ${payload.conversationId}`);

  // Build notification body - prefer message preview, fall back to title
  let body = 'Your response is ready';
  if (payload.messagePreview) {
    // Truncate to reasonable length for push notification
    const maxLength = 150;
    body = payload.messagePreview.length > maxLength
      ? payload.messagePreview.slice(0, maxLength - 1) + '…'
      : payload.messagePreview;
  } else if (payload.title) {
    body = payload.title;
  }

  // Send the push notification
  return sendPushNotification(user.deviceToken, {
    title: 'New response from Claude',
    body,
    conversationId: payload.conversationId,
  });
}
