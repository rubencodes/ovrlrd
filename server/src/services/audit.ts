import { getDb } from '../db/schema';
import { logInfo, logError } from './logger';

export interface AuditEvent {
  userId: string;
  action: string;
  resource: string;
  resourceId?: string;
  metadata?: Record<string, unknown>;
  ip?: string;
  userAgent?: string;
}

// Cached prepared statement for performance
let insertStmt: ReturnType<ReturnType<typeof getDb>['prepare']> | null = null;

/**
 * Get or create the prepared statement for inserting audit logs
 */
function getInsertStatement() {
  if (!insertStmt) {
    const db = getDb();
    insertStmt = db.prepare(`
      INSERT INTO audit_log (user_id, action, resource, resource_id, metadata, ip, user_agent)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `);
  }
  return insertStmt;
}

/**
 * Log an audit event
 * Note: Audit table is created by migrations in schema.ts
 */
export function logAuditEvent(event: AuditEvent): void {
  try {
    const stmt = getInsertStatement();

    stmt.run(
      event.userId,
      event.action,
      event.resource,
      event.resourceId || null,
      event.metadata ? JSON.stringify(event.metadata) : null,
      event.ip || null,
      event.userAgent || null
    );

    logInfo('audit', `${event.action} ${event.resource}`, {
      userId: event.userId,
      resourceId: event.resourceId,
    });
  } catch (error) {
    // Don't let audit logging failures break the app
    // But log the error for monitoring
    logError('audit', `Failed to log audit event: ${error}`);
  }
}

/**
 * Audit actions - only define actions that are actually used
 */
export const AuditActions = {
  AUTH_LOGIN: 'auth.login',
  AUTH_TOKEN_REFRESH: 'auth.token_refresh',
} as const;
