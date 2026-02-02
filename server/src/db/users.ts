import { getDb } from './schema';

export interface User {
  id: string;
  appleUserId: string;
  email: string | null;
  deviceToken: string | null;
  createdAt: string;
  updatedAt: string;
}

interface UserRow {
  id: string;
  apple_user_id: string;
  email: string | null;
  device_token: string | null;
  created_at: string;
  updated_at: string;
}

function rowToUser(row: UserRow): User {
  return {
    id: row.id,
    appleUserId: row.apple_user_id,
    email: row.email,
    deviceToken: row.device_token,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export async function getUserByAppleId(appleUserId: string): Promise<User | null> {
  const db = getDb();
  const row = db.query<UserRow, [string]>(
    'SELECT * FROM users WHERE apple_user_id = ?'
  ).get(appleUserId);

  return row ? rowToUser(row) : null;
}

export async function getUserById(id: string): Promise<User | null> {
  const db = getDb();
  const row = db.query<UserRow, [string]>(
    'SELECT * FROM users WHERE id = ?'
  ).get(id);

  return row ? rowToUser(row) : null;
}

export async function createUser(data: {
  appleUserId: string;
  email?: string;
}): Promise<User> {
  const db = getDb();
  const id = crypto.randomUUID();

  db.query(
    'INSERT INTO users (id, apple_user_id, email) VALUES (?, ?, ?)'
  ).run(id, data.appleUserId, data.email ?? null);

  const user = await getUserById(id);
  if (!user) throw new Error('Failed to create user');
  return user;
}

export async function updateDeviceToken(userId: string, deviceToken: string): Promise<void> {
  const db = getDb();
  db.query(
    "UPDATE users SET device_token = ?, updated_at = datetime('now') WHERE id = ?"
  ).run(deviceToken, userId);
}
