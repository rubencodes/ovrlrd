import { getDb } from './schema';

/**
 * Format a Date as SQLite-compatible timestamp string (UTC)
 * Format: "YYYY-MM-DD HH:MM:SS.mmm"
 */
function formatSqliteTimestamp(date: Date): string {
  const pad = (n: number, width = 2) => n.toString().padStart(width, '0');
  return `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())} ` +
         `${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())}:${pad(date.getUTCSeconds())}.` +
         `${pad(date.getUTCMilliseconds(), 3)}`;
}

export interface Conversation {
  id: string;
  userId: string;
  claudeSessionId: string | null;
  title: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface Message {
  id: string;
  conversationId: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  createdAt: string;
}

interface ConversationRow {
  id: string;
  user_id: string;
  claude_session_id: string | null;
  title: string | null;
  created_at: string;
  updated_at: string;
}

interface MessageRow {
  id: string;
  conversation_id: string;
  role: string;
  content: string;
  created_at: string;
}

function rowToConversation(row: ConversationRow): Conversation {
  return {
    id: row.id,
    userId: row.user_id,
    claudeSessionId: row.claude_session_id,
    title: row.title,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function rowToMessage(row: MessageRow): Message {
  return {
    id: row.id,
    conversationId: row.conversation_id,
    role: row.role as 'user' | 'assistant' | 'system',
    content: row.content,
    createdAt: row.created_at,
  };
}

export async function createConversation(userId: string): Promise<Conversation> {
  const db = getDb();
  const id = crypto.randomUUID();

  db.query(
    'INSERT INTO conversations (id, user_id) VALUES (?, ?)'
  ).run(id, userId);

  const conversation = await getConversation(id);
  if (!conversation) throw new Error('Failed to create conversation');
  return conversation;
}

export async function getConversation(id: string): Promise<Conversation | null> {
  const db = getDb();
  const row = db.query<ConversationRow, [string]>(
    'SELECT * FROM conversations WHERE id = ?'
  ).get(id);

  return row ? rowToConversation(row) : null;
}

export interface PaginationOptions {
  limit?: number;
  cursor?: string; // ISO timestamp for cursor-based pagination
}

export interface PaginatedResult<T> {
  items: T[];
  hasMore: boolean;
  nextCursor: string | null;
}

const DEFAULT_PAGE_SIZE = 20;

export async function getConversations(
  userId: string,
  options: PaginationOptions = {}
): Promise<PaginatedResult<Conversation>> {
  const db = getDb();
  const limit = options.limit || DEFAULT_PAGE_SIZE;

  let query: string;
  let params: (string | number)[];

  if (options.cursor) {
    query = `
      SELECT * FROM conversations
      WHERE user_id = ? AND updated_at < ?
      ORDER BY updated_at DESC
      LIMIT ?
    `;
    params = [userId, options.cursor, limit + 1];
  } else {
    query = `
      SELECT * FROM conversations
      WHERE user_id = ?
      ORDER BY updated_at DESC
      LIMIT ?
    `;
    params = [userId, limit + 1];
  }

  const rows = db.query<ConversationRow, (string | number)[]>(query).all(...params);

  const hasMore = rows.length > limit;
  const items = rows.slice(0, limit).map(rowToConversation);
  const lastItem = items[items.length - 1];
  const nextCursor = hasMore && lastItem ? lastItem.updatedAt : null;

  return { items, hasMore, nextCursor };
}

export async function createMessage(data: {
  conversationId: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
}): Promise<Message> {
  const db = getDb();
  const id = crypto.randomUUID();
  const now = formatSqliteTimestamp(new Date());

  // Use transaction for atomicity - both operations succeed or both fail
  db.exec('BEGIN TRANSACTION');
  try {
    db.query(
      'INSERT INTO messages (id, conversation_id, role, content, created_at) VALUES (?, ?, ?, ?, ?)'
    ).run(id, data.conversationId, data.role, data.content, now);

    db.query(
      'UPDATE conversations SET updated_at = ? WHERE id = ?'
    ).run(now, data.conversationId);

    db.exec('COMMIT');
  } catch (error) {
    db.exec('ROLLBACK');
    throw error;
  }

  // Return the created message (constructed from known values to avoid extra query)
  return {
    id,
    conversationId: data.conversationId,
    role: data.role,
    content: data.content,
    createdAt: now,
  };
}

export async function getMessage(id: string): Promise<Message | null> {
  const db = getDb();
  const row = db.query<MessageRow, [string]>(
    'SELECT * FROM messages WHERE id = ?'
  ).get(id);

  return row ? rowToMessage(row) : null;
}

export async function getMessages(
  conversationId: string,
  options: PaginationOptions = {}
): Promise<PaginatedResult<Message>> {
  const db = getDb();
  const limit = options.limit || 50; // More messages per page since they're smaller

  let query: string;
  let params: (string | number)[];

  if (options.cursor) {
    // For messages, we paginate backwards (load older messages)
    // cursor is the createdAt of the oldest message we have
    query = `
      SELECT * FROM messages
      WHERE conversation_id = ? AND created_at < ?
      ORDER BY created_at DESC
      LIMIT ?
    `;
    params = [conversationId, options.cursor, limit + 1];
  } else {
    // Initial load: get the most recent messages
    query = `
      SELECT * FROM messages
      WHERE conversation_id = ?
      ORDER BY created_at DESC
      LIMIT ?
    `;
    params = [conversationId, limit + 1];
  }

  const rows = db.query<MessageRow, (string | number)[]>(query).all(...params);

  const hasMore = rows.length > limit;
  // Reverse to get chronological order (oldest first)
  const items = rows.slice(0, limit).reverse().map(rowToMessage);
  const firstItem = items[0]; // The oldest message
  const nextCursor = hasMore && firstItem ? firstItem.createdAt : null;

  return { items, hasMore, nextCursor };
}

export async function updateClaudeSessionId(
  conversationId: string,
  claudeSessionId: string
): Promise<void> {
  const db = getDb();
  db.query(
    "UPDATE conversations SET claude_session_id = ?, updated_at = datetime('now') WHERE id = ?"
  ).run(claudeSessionId, conversationId);
}

export async function deleteConversation(conversationId: string): Promise<void> {
  const db = getDb();
  // Messages are deleted automatically via ON DELETE CASCADE
  db.query('DELETE FROM conversations WHERE id = ?').run(conversationId);
}

export async function updateConversationTitle(
  conversationId: string,
  title: string
): Promise<void> {
  const db = getDb();
  db.query(
    "UPDATE conversations SET title = ?, updated_at = datetime('now') WHERE id = ?"
  ).run(title, conversationId);
}
