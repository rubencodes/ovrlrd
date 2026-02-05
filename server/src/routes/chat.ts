import { Hono } from 'hono';
import { streamSSE } from 'hono/streaming';
import type { AuthContext } from '../middleware/auth';
import {
  createConversation,
  getConversations,
  createMessage,
  getMessages,
  updateClaudeSessionId,
  deleteConversation,
  updateConversationTitle,
} from '../db/conversations';
import { runClaude } from '../services/claude';
import { runClaudeStreaming, type PermissionDenial } from '../services/claude-stream';
import { generateTitle } from '../services/title-generator';
import { logError, logInfo } from '../services/logger';
import { authorizeConversation } from '../utils/authorization';
import {
  chatMessageSchema,
  chatStreamSchema,
  permissionEventSchema,
  paginationSchema,
  parseBody,
  parseQuery,
} from '../validation/schemas';
import { sendMessageReadyNotification } from '../services/notification';

const chat = new Hono<AuthContext>();

// =============================================================================
// Types
// =============================================================================

interface Conversation {
  id: string;
  claudeSessionId: string | null;
  title: string | null;
}

interface StreamResult {
  sessionId: string | null;
  permissionDenials?: PermissionDenial[];
  error?: string;
}

type SSEStream = { writeSSE: (data: { data: string }) => void };

// =============================================================================
// SSE Helpers
// =============================================================================

function writeSSEEvent(stream: SSEStream, type: string, data: Record<string, unknown> = {}) {
  stream.writeSSE({ data: JSON.stringify({ type, ...data }) });
}

/**
 * Deduplicate permission denials by tool_name + tool_input.
 * Claude sometimes retries the same tool call multiple times when denied,
 * resulting in duplicate entries with different tool_use_ids.
 */
function deduplicatePermissionDenials(denials: PermissionDenial[]): PermissionDenial[] {
  const seen = new Set<string>();
  return denials.filter((denial) => {
    const key = `${denial.tool_name}:${JSON.stringify(denial.tool_input)}`;
    if (seen.has(key)) {
      return false;
    }
    seen.add(key);
    return true;
  });
}

// =============================================================================
// Non-Streaming Message Handler
// =============================================================================

async function sendNonStreamingMessage(
  conversation: Conversation,
  message: string
): Promise<{ text: string }> {
  const response = await runClaude(message, conversation.claudeSessionId);

  if (response.sessionId && response.sessionId !== conversation.claudeSessionId) {
    await updateClaudeSessionId(conversation.id, response.sessionId);
  }

  await createMessage({
    conversationId: conversation.id,
    role: 'assistant',
    content: response.text,
  });

  return { text: response.text };
}

// =============================================================================
// Streaming: Setup & Callbacks
// =============================================================================

interface StreamingState {
  segments: string[];
  currentSegment: string;
  result: StreamResult;
}

function createStreamingCallbacks(
  stream: SSEStream,
  conversation: Conversation,
  state: StreamingState
) {
  return {
    onChunk: (text: string) => {
      state.currentSegment += text;
      writeSSEEvent(stream, 'chunk', { content: text });
    },

    onSegmentEnd: (content: string) => {
      if (content.trim()) {
        state.segments.push(content);
        writeSSEEvent(stream, 'segment_end', { conversationId: conversation.id, content });
      }
      state.currentSegment = '';
    },

    onToolStart: (toolName: string) => {
      writeSSEEvent(stream, 'tool_start', { toolName });
    },

    onToolEnd: (toolName: string) => {
      writeSSEEvent(stream, 'tool_end', { toolName });
    },

    onComplete: (result: string, sessionId: string | null, permissionDenials?: PermissionDenial[]) => {
      // Deduplicate permission denials - Claude sometimes retries the same tool call
      // multiple times when denied, resulting in duplicate entries with different tool_use_ids
      const deduplicatedDenials = permissionDenials
        ? deduplicatePermissionDenials(permissionDenials)
        : undefined;

      state.result = { sessionId, permissionDenials: deduplicatedDenials };

      // Send terminal event immediately to ensure client receives it before connection closes
      if (deduplicatedDenials && deduplicatedDenials.length > 0) {
        logInfo('chat', `Permission required for ${deduplicatedDenials.length} tool(s)`);
        writeSSEEvent(stream, 'permission_required', {
          conversationId: conversation.id,
          denials: deduplicatedDenials,
        });
      } else if (state.currentSegment.trim() || state.segments.length > 0) {
        writeSSEEvent(stream, 'complete', { conversationId: conversation.id });
      } else {
        writeSSEEvent(stream, 'no_response', {
          conversationId: conversation.id,
          message: 'This command completed but produced no visible output.',
        });
      }
    },

    onError: (error: string) => {
      logError('chat', `Stream error: ${error}`);
      state.result = { sessionId: null, error };
      writeSSEEvent(stream, 'error', { message: error });
    },
  };
}

// =============================================================================
// Streaming: Post-Stream Processing
// =============================================================================

async function persistStreamResult(
  stream: SSEStream,
  conversation: Conversation,
  userId: string,
  message: string,
  state: StreamingState
) {
  const { result, segments, currentSegment } = state;

  // Update session ID if changed
  if (result.sessionId && result.sessionId !== conversation.claudeSessionId) {
    await updateClaudeSessionId(conversation.id, result.sessionId);
  }

  if (result.permissionDenials && result.permissionDenials.length > 0) {
    // Store any partial response before permission request
    await storeSegments(conversation.id, segments, currentSegment);
  } else {
    // Include final segment
    const allSegments = currentSegment.trim()
      ? [...segments, currentSegment]
      : segments;

    if (allSegments.length > 0) {
      // Store all segments as messages
      for (const segmentContent of allSegments) {
        await createMessage({
          conversationId: conversation.id,
          role: 'assistant',
          content: segmentContent,
        });
      }

      // Generate and send title update
      const newTitle = await generateAndUpdateTitle(conversation, message, allSegments);
      if (newTitle) {
        writeSSEEvent(stream, 'title_update', { conversationId: conversation.id, title: newTitle });
      }

      // Send push notification
      sendMessageReadyNotification(userId, {
        conversationId: conversation.id,
        title: newTitle ?? conversation.title ?? undefined,
        messagePreview: allSegments.join('\n').trim(),
      });
    }
  }
}

async function storeSegments(conversationId: string, segments: string[], currentSegment: string) {
  for (const segmentContent of segments) {
    await createMessage({ conversationId, role: 'assistant', content: segmentContent });
  }
  if (currentSegment.trim()) {
    await createMessage({ conversationId, role: 'assistant', content: currentSegment });
  }
}

async function generateAndUpdateTitle(
  conversation: Conversation,
  userMessage: string,
  segments: string[]
): Promise<string | null> {
  try {
    logInfo('chat', `Generating title for conversation ${conversation.id}, current title: ${conversation.title}`);
    const recentMessages = [
      { role: 'user', content: userMessage },
      { role: 'assistant', content: segments.join('\n') },
    ];
    const titleResult = await generateTitle(conversation.title, recentMessages);
    logInfo('chat', `Title result: ${JSON.stringify(titleResult)}`);

    if (titleResult.title) {
      await updateConversationTitle(conversation.id, titleResult.title);
      logInfo('chat', `Updated title to: ${titleResult.title}`);
      return titleResult.title;
    }
  } catch (titleError) {
    logError('chat', `Title generation failed: ${titleError}`);
  }
  return null;
}

// =============================================================================
// Streaming: Main Handler
// =============================================================================

async function handleStreamingResponse(
  stream: SSEStream,
  message: string,
  conversation: Conversation,
  userId: string,
  allowedTools?: string[]
) {
  const state: StreamingState = {
    segments: [],
    currentSegment: '',
    result: { sessionId: null },
  };

  const callbacks = createStreamingCallbacks(stream, conversation, state);

  await runClaudeStreaming(
    message,
    conversation.id,
    conversation.claudeSessionId,
    callbacks,
    { allowedTools }
  );

  // If there was an error, don't do DB operations
  if (state.result.error) {
    return;
  }

  try {
    await persistStreamResult(stream, conversation, userId, message, state);
  } catch (dbError) {
    logError('chat', `Failed to store response: ${dbError}`);
    writeSSEEvent(stream, 'error', { message: 'Failed to store response' });
  }
}

// =============================================================================
// Streaming Request Setup
// =============================================================================

async function storePreStreamMessage(
  conversationId: string,
  message: string,
  allowedTools?: string[]
) {
  if (allowedTools && allowedTools.length > 0) {
    await createMessage({
      conversationId,
      role: 'system',
      content: `✓ Approved: ${allowedTools.join(', ')}`,
    });
  } else {
    await createMessage({
      conversationId,
      role: 'user',
      content: message,
    });
  }
}

// =============================================================================
// Routes
// =============================================================================

// GET /chat - List conversations
chat.get('/', async (c) => {
  const userId = c.get('userId');
  const { limit, cursor } = parseQuery(new URL(c.req.url), paginationSchema);

  const result = await getConversations(userId, { limit, cursor });
  return c.json({
    conversations: result.items,
    hasMore: result.hasMore,
    nextCursor: result.nextCursor,
  });
});

// POST /chat - Send a message (creates new conversation)
chat.post('/', async (c) => {
  const userId = c.get('userId');
  const { message } = await parseBody(c.req.raw, chatMessageSchema);

  const conversation = await createConversation(userId);

  await createMessage({
    conversationId: conversation.id,
    role: 'user',
    content: message,
  });

  try {
    const response = await sendNonStreamingMessage(conversation, message);
    return c.json({ conversationId: conversation.id, message: response.text });
  } catch (error) {
    logError('chat', error);
    return c.json({ error: 'Failed to get response from Claude' }, 500);
  }
});

// POST /chat/stream - Stream to new conversation (creates it)
chat.post('/stream', async (c) => {
  const userId = c.get('userId');
  const { message, allowedTools } = await parseBody(c.req.raw, chatStreamSchema);

  const conversation = await createConversation(userId);

  try {
    await storePreStreamMessage(conversation.id, message, allowedTools);
  } catch (dbError) {
    logError('chat', `Failed to store message: ${dbError}`);
    const errorMessage = dbError instanceof Error ? dbError.message : 'Database error';
    return c.json({ error: `Failed to store message: ${errorMessage}` }, 500);
  }

  logInfo('chat', `Streaming request for new conversation: ${conversation.id}`);

  return streamSSE(c, async (stream) => {
    await handleStreamingResponse(stream, message, conversation, userId, allowedTools);
  });
});

// GET /chat/:id - Get conversation with messages
chat.get('/:id', async (c) => {
  const conversationId = c.req.param('id');
  const authResult = await authorizeConversation(c, conversationId);

  if (!authResult.authorized) {
    return c.json({ error: authResult.error }, authResult.status);
  }

  const { limit, cursor } = parseQuery(new URL(c.req.url), paginationSchema);
  const result = await getMessages(conversationId, { limit, cursor });

  return c.json({
    conversation: authResult.conversation,
    messages: result.items,
    hasMore: result.hasMore,
    nextCursor: result.nextCursor,
  });
});

// POST /chat/:id - Send message to existing conversation
chat.post('/:id', async (c) => {
  const conversationId = c.req.param('id');
  const authResult = await authorizeConversation(c, conversationId);

  if (!authResult.authorized) {
    return c.json({ error: authResult.error }, authResult.status);
  }

  const { message } = await parseBody(c.req.raw, chatMessageSchema);
  const conversation = authResult.conversation;

  await createMessage({
    conversationId: conversation.id,
    role: 'user',
    content: message,
  });

  try {
    const response = await sendNonStreamingMessage(conversation, message);
    return c.json({ conversationId: conversation.id, message: response.text });
  } catch (error) {
    logError('chat', error);
    return c.json({ error: 'Failed to get response from Claude' }, 500);
  }
});

// DELETE /chat/:id - Delete a conversation
chat.delete('/:id', async (c) => {
  const conversationId = c.req.param('id');
  const authResult = await authorizeConversation(c, conversationId);

  if (!authResult.authorized) {
    logInfo('chat', `Delete rejected: ${conversationId}`);
    return c.json({ error: authResult.error }, authResult.status);
  }

  await deleteConversation(conversationId);
  logInfo('chat', `Deleted conversation: ${conversationId}`);
  return c.json({ success: true });
});

// POST /chat/:id/stream - Stream to existing conversation
chat.post('/:id/stream', async (c) => {
  const conversationId = c.req.param('id');
  const authResult = await authorizeConversation(c, conversationId);

  if (!authResult.authorized) {
    return c.json({ error: authResult.error }, authResult.status);
  }

  const { message, allowedTools } = await parseBody(c.req.raw, chatStreamSchema);
  const conversation = authResult.conversation;
  const userId = c.get('userId');

  try {
    await storePreStreamMessage(conversation.id, message, allowedTools);
  } catch (dbError) {
    logError('chat', `Failed to store message: ${dbError}`);
    const errorMessage = dbError instanceof Error ? dbError.message : 'Database error';
    return c.json({ error: `Failed to store message: ${errorMessage}` }, 500);
  }

  logInfo('chat', `Streaming request for conversation: ${conversation.id}${allowedTools?.length ? ` with allowed tools: ${allowedTools.join(', ')}` : ''}`);

  return streamSSE(c, async (stream) => {
    await handleStreamingResponse(stream, message, conversation, userId, allowedTools);
  });
});

// POST /chat/:id/events - Store a permission event (approval/denial) without triggering Claude
chat.post('/:id/events', async (c) => {
  const conversationId = c.req.param('id');
  const authResult = await authorizeConversation(c, conversationId);

  if (!authResult.authorized) {
    return c.json({ error: authResult.error }, authResult.status);
  }

  const { role, content } = await parseBody(c.req.raw, permissionEventSchema);

  const msg = await createMessage({
    conversationId,
    role,
    content,
  });

  return c.json({ success: true, messageId: msg.id });
});

export { chat as chatRoutes };
