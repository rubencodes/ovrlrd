import { Database } from 'bun:sqlite';
import { config } from '../config';
import { existsSync, copyFileSync } from 'node:fs';

let db: Database;

// Migration version definitions
interface Migration {
  version: number;
  name: string;
  up: (db: Database) => void;
}

const migrations: Migration[] = [
  {
    version: 1,
    name: 'initial_schema',
    up: (db) => {
      db.exec(`
        CREATE TABLE IF NOT EXISTS users (
          id TEXT PRIMARY KEY,
          apple_user_id TEXT UNIQUE NOT NULL,
          email TEXT,
          device_token TEXT,
          created_at TEXT DEFAULT (datetime('now')),
          updated_at TEXT DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS conversations (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          claude_session_id TEXT,
          title TEXT,
          created_at TEXT DEFAULT (datetime('now')),
          updated_at TEXT DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS messages (
          id TEXT PRIMARY KEY,
          conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
          role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
          content TEXT NOT NULL,
          created_at TEXT DEFAULT (datetime('now'))
        );

        -- Basic indexes
        CREATE INDEX IF NOT EXISTS idx_users_apple_user_id ON users(apple_user_id);
        CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON conversations(user_id);
        CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON messages(conversation_id);
      `);
    },
  },
  {
    version: 2,
    name: 'add_pagination_indexes',
    up: (db) => {
      db.exec(`
        -- Composite index for conversation pagination (user_id + updated_at DESC)
        CREATE INDEX IF NOT EXISTS idx_conversations_user_updated
          ON conversations(user_id, updated_at DESC);

        -- Composite index for message pagination (conversation_id + created_at DESC)
        CREATE INDEX IF NOT EXISTS idx_messages_conversation_created
          ON messages(conversation_id, created_at DESC);
      `);
    },
  },
  {
    version: 3,
    name: 'add_audit_log_table',
    up: (db) => {
      db.exec(`
        CREATE TABLE IF NOT EXISTS audit_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL,
          action TEXT NOT NULL,
          resource TEXT NOT NULL,
          resource_id TEXT,
          metadata TEXT,
          ip TEXT,
          user_agent TEXT,
          created_at TEXT DEFAULT (datetime('now'))
        );

        -- Composite index for user audit queries
        CREATE INDEX IF NOT EXISTS idx_audit_user_created
          ON audit_log(user_id, created_at DESC);

        -- Index for action filtering
        CREATE INDEX IF NOT EXISTS idx_audit_action
          ON audit_log(action);
      `);
    },
  },
];

/**
 * Create a backup of the database before running migrations
 */
function createBackup(dbPath: string): string | null {
  if (!existsSync(dbPath)) {
    return null;
  }

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backupPath = `${dbPath}.backup-${timestamp}`;

  try {
    copyFileSync(dbPath, backupPath);
    console.log(`Database backup created: ${backupPath}`);
    return backupPath;
  } catch (error) {
    console.error(`Failed to create backup: ${error}`);
    return null;
  }
}

/**
 * Get the current migration version from the database
 */
function getCurrentVersion(db: Database): number {
  try {
    const row = db.query<{ version: number }, []>(
      'SELECT MAX(version) as version FROM migrations'
    ).get();
    return row?.version ?? 0;
  } catch {
    // Table doesn't exist yet
    return 0;
  }
}

/**
 * Run database migrations with version tracking
 */
function runMigrations(db: Database): void {
  // Create migrations table if it doesn't exist
  db.exec(`
    CREATE TABLE IF NOT EXISTS migrations (
      version INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      applied_at TEXT DEFAULT (datetime('now'))
    );
  `);

  const currentVersion = getCurrentVersion(db);
  const pendingMigrations = migrations.filter(m => m.version > currentVersion);

  if (pendingMigrations.length === 0) {
    return;
  }

  console.log(`Running ${pendingMigrations.length} pending migration(s)...`);

  // Create backup before running migrations
  const backupPath = createBackup(config.dbPath);

  try {
    for (const migration of pendingMigrations) {
      console.log(`  Running migration ${migration.version}: ${migration.name}`);

      // Run migration in a transaction
      db.exec('BEGIN TRANSACTION');
      try {
        migration.up(db);

        // Record the migration
        db.query(
          'INSERT INTO migrations (version, name) VALUES (?, ?)'
        ).run(migration.version, migration.name);

        db.exec('COMMIT');
      } catch (error) {
        db.exec('ROLLBACK');
        throw error;
      }
    }

    console.log('All migrations completed successfully.');
  } catch (error) {
    console.error('Migration failed:', error);
    if (backupPath) {
      console.error(`Restore from backup: ${backupPath}`);
    }
    throw error;
  }
}

/**
 * Handle legacy migration from old schema (pre-version tracking)
 * This checks for the old 'system' role migration need and handles it
 */
function handleLegacyMigration(db: Database): void {
  // Check if migrations table exists
  const migrationsTableExists = db.query<{ name: string }, []>(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='migrations'"
  ).get();

  if (migrationsTableExists) {
    // Already using new migration system
    return;
  }

  // Check if tables exist at all
  const usersTableExists = db.query<{ name: string }, []>(
    "SELECT name FROM sqlite_master WHERE type='table' AND name='users'"
  ).get();

  if (!usersTableExists) {
    // Fresh database, no legacy migration needed
    return;
  }

  console.log('Detected existing database without migration tracking. Setting up...');

  // Check if messages table needs the 'system' role migration
  const messagesTableInfo = db.query<{ sql: string }, []>(
    "SELECT sql FROM sqlite_master WHERE type='table' AND name='messages'"
  ).get();

  const needsSystemRoleMigration = messagesTableInfo?.sql && !messagesTableInfo.sql.includes("'system'");

  // Create backup before any changes
  createBackup(config.dbPath);

  if (needsSystemRoleMigration) {
    console.log('Migrating messages table to support system role...');
    db.exec(`
      CREATE TABLE IF NOT EXISTS messages_new (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
        role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
        content TEXT NOT NULL,
        created_at TEXT DEFAULT (datetime('now'))
      );

      INSERT INTO messages_new SELECT * FROM messages;
      DROP TABLE messages;
      ALTER TABLE messages_new RENAME TO messages;
      CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON messages(conversation_id);
    `);
    console.log('Messages table migration complete.');
  }

  // Create migrations table and mark existing migrations as applied
  db.exec(`
    CREATE TABLE IF NOT EXISTS migrations (
      version INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      applied_at TEXT DEFAULT (datetime('now'))
    );

    INSERT OR IGNORE INTO migrations (version, name, applied_at)
    VALUES (1, 'initial_schema (legacy)', datetime('now'));
  `);

  console.log('Migration tracking initialized.');
}

export function getDb(): Database {
  if (!db) {
    db = new Database(config.dbPath);
    db.exec('PRAGMA journal_mode = WAL');
    db.exec('PRAGMA foreign_keys = ON');
  }
  return db;
}

/**
 * Close the database connection (for graceful shutdown)
 */
export function closeDb(): void {
  if (db) {
    db.close();
  }
}

/**
 * Check database health by running a simple query
 */
export function checkDbHealth(): { ok: boolean; error?: string } {
  try {
    const database = getDb();
    const result = database.query<{ result: number }, []>('SELECT 1 as result').get();
    return { ok: result?.result === 1 };
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : 'Unknown error' };
  }
}

export async function initDb(): Promise<void> {
  const database = getDb();

  // Handle legacy databases without migration tracking
  handleLegacyMigration(database);

  // Run any pending migrations
  runMigrations(database);

  console.log('Database initialized');
}
