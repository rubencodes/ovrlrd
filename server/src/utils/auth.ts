import type { Context } from 'hono';
import { getConversation, type Conversation } from '../db/conversations';

/**
 * Result of conversation authorization check
 */
export type ConversationAuthResult =
  | { authorized: true; conversation: Conversation }
  | { authorized: false; error: string; status: 404 };

/**
 * Verify the current user owns the specified conversation
 * Returns the conversation if authorized, or an error response
 */
export async function authorizeConversation(
  c: Context,
  conversationId: string
): Promise<ConversationAuthResult> {
  const userId = c.get('userId');
  const conversation = await getConversation(conversationId);

  if (!conversation || conversation.userId !== userId) {
    return {
      authorized: false,
      error: 'Conversation not found',
      status: 404,
    };
  }

  return {
    authorized: true,
    conversation,
  };
}
