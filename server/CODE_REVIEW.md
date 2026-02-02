# Server Code Review - Production Readiness Audit

> **Status**: All phases completed. See implementation notes at the bottom.


## Executive Summary

A team of four staff-level engineers reviewed the server codebase for security, architecture, async patterns, and database design. We identified **50+ issues** ranging from critical security vulnerabilities to minor code smells.

### Issue Counts by Severity

| Severity | Count | Description |
|----------|-------|-------------|
| Critical | 8 | Security vulnerabilities, data loss risks |
| High | 18 | Significant bugs, resource leaks, missing safety checks |
| Medium | 20 | Code quality, maintainability, minor security |
| Low | 10 | Style, optimization, minor improvements |

---

## Critical Issues (Must Fix Before Production)

### 1. Hardcoded JWT Secret Default
**File:** `src/config.ts:3`
```typescript
jwtSecret: process.env.JWT_SECRET || 'dev-secret-change-in-production',
```
**Risk:** If `JWT_SECRET` not set, attackers can forge valid tokens.
**Fix:** Fail startup if `JWT_SECRET` is not configured.

### 2. API Key Allows Open Access When Not Set
**File:** `src/middleware/apiKey.ts:19-23`
```typescript
if (!config.apiKey) {
  console.warn('WARNING: No API_KEY configured...');
  return next(); // Allows request through!
}
```
**Risk:** Production API completely open if env var missing.
**Fix:** Fail startup or reject requests if `API_KEY` not configured.

### 3. Database Files Not in .gitignore
**Files:** `ovrlrd.db`, `data.db` exist but `.gitignore` only covers `.env`
**Risk:** User data, messages, tokens could be committed to git.
**Fix:** Add `*.db`, `*.p8`, `*.pem`, `*.key`, `debug.log` to `.gitignore`.

### 4. Fire-and-Forget Logging
**File:** `src/services/logger.ts:25,34,40`
```typescript
writeLog(line); // async but not awaited, no .catch()
```
**Risk:** Unhandled promise rejections can crash the process.
**Fix:** Either make logging synchronous or add `.catch(() => {})`.

### 5. No Subprocess Timeouts
**Files:** `src/services/claude.ts`, `src/services/claude-stream.ts`
**Risk:** Hung Claude CLI process blocks request forever.
**Fix:** Add timeout with `AbortSignal.timeout()` or manual timer + `proc.kill()`.

### 6. Destructive Migration Without Backup
**File:** `src/db/schema.ts:16-42`
```typescript
// Drops messages table, recreates, copies data
// If INSERT fails partway, data is LOST
```
**Risk:** Data loss during migration.
**Fix:** Create backup before migration, add version tracking.

### 7. onComplete Callback Not Awaited
**File:** `src/routes/chat.ts:323-366` / `src/services/claude-stream.ts:251`
```typescript
session.onComplete(...); // async callback, not awaited
```
**Risk:** Database writes in callback could be interrupted.
**Fix:** Restructure to await database operations.

### 8. Token Refresh Grace Period of 7 Days
**File:** `src/routes/auth.ts:149-151`
**Risk:** Stolen tokens valid for 7 days after "expiration".
**Fix:** Reduce to hours (e.g., 1-4 hours).

---

## High Priority Issues

### Security

| # | File | Issue |
|---|------|-------|
| 9 | `src/app.ts:27` | Overly permissive CORS - allows any origin |
| 10 | `src/middleware/rateLimit.ts` | Rate limiting defined but **never applied** to routes |
| 11 | Multiple files | Logging exposes PII (emails, user IDs, partial messages) |

### Resource Management

| # | File | Issue |
|---|------|-------|
| 12 | `src/services/claude.ts` | No `proc.kill()` on error - zombie processes |
| 13 | `src/services/claude-stream.ts:104-186` | stdout/stderr readers never released |
| 14 | `src/services/claude-stream.ts:130-131` | No try/catch around stdin operations |
| 15 | `src/services/apns.ts:11-40` | Race condition in token generation |
| 16 | `src/services/claude-stream.ts:44,126` | Session map overwrites can orphan processes |

### Database

| # | File | Issue |
|---|------|-------|
| 17 | `src/db/conversations.ts:131-151` | `createMessage()` not atomic - inconsistent state on failure |
| 18 | `src/db/schema.ts` | Missing composite indexes for pagination queries |
| 19 | `src/db/schema.ts` | No migration version tracking - can't add migrations safely |
| 20 | `src/middleware/rateLimit.ts:9-10` | In-memory rate limiting doesn't work across instances |

### Error Handling

| # | File | Issue |
|---|------|-------|
| 21 | `src/services/apns.ts:85-87` | Push notification errors swallowed |
| 22 | `src/services/audit.ts:71-74` | Audit failures silently swallowed |
| 23 | `src/routes/auth.ts:24-31` | No timeout on Apple JWKS fetch |
| 24 | `src/services/apns.ts:42-88` | No retry logic for push notifications |

---

## Medium Priority Issues

### Code Duplication

| # | Files | Issue |
|---|-------|-------|
| 25 | `claude.ts` + `claude-stream.ts` | Duplicate workDir, additionalDirs, PATH, spawn config |
| 26 | `src/routes/chat.ts` | Conversation auth check duplicated 5 times |
| 27 | `auth.ts`, `rateLimit.ts`, `apiKey.ts` | IP extraction logic duplicated 4 times |
| 28 | `src/routes/chat.ts:90-95,227-231` | Allowed tools message creation duplicated |

### Type Safety

| # | File | Issue |
|---|------|-------|
| 29 | `src/routes/auth.ts:31` | Double type assertion through `unknown` |
| 30 | `src/db/conversations.ts:52` | Role cast without validation |
| 31 | Multiple route files | No runtime validation on request bodies |
| 32 | `src/config.ts:2` | Port can become `NaN` without validation |

### Separation of Concerns

| # | File | Issue |
|---|------|-------|
| 33 | `src/routes/chat.ts:280-395` | 115-line `handleStreamingResponse()` mixes concerns |
| 34 | `src/routes/auth.ts:54-131` | 77-line handler with mixed concerns |
| 35 | `src/services/audit.ts` | `initAuditTable()` creates schema but lives in services/ |

### Unused Code

| # | File | Issue |
|---|------|-------|
| 36 | `src/services/apns.ts` | `sendPushNotification()` never called |
| 37 | `src/services/claude-stream.ts:274-280` | `cancelStream()` never called |
| 38 | `src/services/audit.ts:86-100` | Many `AuditActions` defined but never used |
| 39 | `src/middleware/rateLimit.ts:2` | `logError` imported but unused |

### Async Patterns

| # | File | Issue |
|---|------|-------|
| 40 | `src/db/conversations.ts` | All DB functions marked `async` but operations are sync |
| 41 | `src/services/claude-stream.ts:155-168` | JSON parse errors silently ignored |
| 42 | `src/services/logger.ts:10-17` | Fallback overwrites entire log file |

---

## Low Priority Issues

| # | File | Issue |
|---|------|-------|
| 43 | Middleware files | Inconsistent middleware creation style |
| 44 | `src/routes/auth.ts:8` | `const auth` exported as `authRoutes` - naming |
| 45 | `src/routes/chat.ts:103` | Magic number `50` for title truncation |
| 46 | Multiple files | Token expiration `24h` repeated as magic number |
| 47 | `src/db/schema.ts` | TEXT for timestamps instead of INTEGER |
| 48 | `src/db/conversations.ts` | `SELECT *` used everywhere |
| 49 | `src/middleware/rateLimit.ts:13-20` | setInterval never cleared |
| 50 | `src/config.ts:14` | Config object not frozen |

---

## Positive Findings

The codebase does several things well:

1. **Parameterized SQL queries** - No SQL injection risk
2. **Constant-time API key comparison** - Timing attack resistant
3. **JWT verification** - Proper use of jose library
4. **Authorization checks** - Conversation ownership verified
5. **Audit logging** - Security events tracked
6. **Foreign key constraints** - Referential integrity in schema
7. **WAL mode** - SQLite configured for better concurrency
8. **Consistent naming** - camelCase functions, PascalCase types

---

## Recommended Fix Order

### Phase 1: Critical Security (Day 1)
1. Update `.gitignore` with `*.db`, `*.p8`, `*.pem`, `*.key`, `debug.log`
2. Make `JWT_SECRET` required (fail startup if missing)
3. Make `API_KEY` required in production (fail startup if missing)
4. Reduce token refresh grace period to 4 hours
5. Configure CORS with specific allowed origins

### Phase 2: Stability (Day 2-3)
6. Add subprocess timeouts (30-60 seconds)
7. Fix fire-and-forget logging
8. Add try/catch and resource cleanup in Claude services
9. Fix race condition in APNS token generation
10. Await onComplete callback or restructure

### Phase 3: Database (Day 4)
11. Add composite indexes for pagination
12. Wrap multi-step operations in transactions
13. Add migration version tracking
14. Add backup before destructive migrations

### Phase 4: Code Quality (Day 5+)
15. Apply rate limiting middleware
16. Extract shared Claude configuration
17. Add request body validation (Zod)
18. Extract conversation auth check to utility
19. Remove/document unused code
20. Add fetch timeouts and retry logic

---

## Files to Create/Modify

### New Files
- `src/utils/ip.ts` - Extract IP address helper
- `src/utils/claude-config.ts` - Shared Claude spawn config
- `src/middleware/requireAuth.ts` - Conversation authorization helper
- `src/validation/schemas.ts` - Zod schemas for request bodies

### Modified Files
- `.gitignore` - Add sensitive file patterns
- `src/config.ts` - Add validation, fail on missing required values
- `src/app.ts` - Configure CORS, apply rate limiting
- `src/services/logger.ts` - Fix async handling
- `src/services/claude.ts` - Add timeout, cleanup
- `src/services/claude-stream.ts` - Add timeout, cleanup, fix race
- `src/services/apns.ts` - Add mutex, retry, propagate errors
- `src/db/schema.ts` - Add indexes, migration tracking
- `src/db/conversations.ts` - Add transactions
- `src/routes/auth.ts` - Reduce grace period, add timeout
- `src/routes/chat.ts` - Extract helpers, await callbacks

---

## Implementation Summary

All four phases have been completed. Here's what was implemented:

### Phase 1: Critical Security ✅
- `.gitignore` updated with `*.db`, `*.p8`, `*.pem`, `*.key`, `debug.log`
- `config.ts` rewritten with `requireEnv()` - fails in production if secrets missing
- `apiKey.ts` returns 500 in production if API key not configured
- Token refresh grace period reduced from 7 days to 4 hours
- CORS configuration added with environment-specific behavior
- `.env.example` updated with documentation

### Phase 2: Stability ✅
- `logger.ts` changed to synchronous file operations (no more fire-and-forget)
- `claude-config.ts` created with shared configuration
- `claude.ts` and `claude-stream.ts` updated with:
  - 2-minute subprocess timeouts
  - Proper resource cleanup (kill process, release readers)
  - Session overwrite protection
- `apns.ts` updated with:
  - Mutex pattern for token refresh (prevents thundering herd)
  - 30-second fetch timeout
  - Exponential backoff retry (3 attempts)
  - Returns `PushResult` instead of swallowing errors
- `chat.ts` refactored so DB operations happen after streaming completes

### Phase 3: Database ✅
- `schema.ts` completely rewritten with migration system:
  - `migrations` table for version tracking
  - Automatic backup before migrations
  - Transaction-wrapped migrations with rollback
  - Legacy database upgrade path
- Added migrations:
  - v1: Initial schema
  - v2: Pagination indexes (`idx_conversations_user_updated`, `idx_messages_conversation_created`)
  - v3: Audit log table with indexes
- `conversations.ts` updated with transaction for `createMessage()`
- `audit.ts` cleaned up (table creation moved to migrations, cached prepared statement)

### Phase 4: Code Quality ✅
- Rate limiting applied to routes in `app.ts`:
  - `authRateLimit` on `/auth/*`
  - `standardRateLimit` on `/chat`
  - `claudeRateLimit` on `/chat/stream` and `/chat/:id/stream`
- `validation/schemas.ts` created with Zod schemas for all request bodies
- `utils/request.ts` created with `getClientIp()` and `getUserAgent()`
- `utils/authorization.ts` created with `authorizeConversation()` helper
- `auth.ts` and `chat.ts` updated to use new utilities
- `rateLimit.ts` fixed: removed unused import, added `unref()` to cleanup interval
- Validation errors now return 400 with helpful messages

### New Files Created
- `src/services/claude-config.ts`
- `src/validation/schemas.ts`
- `src/utils/request.ts`
- `src/utils/authorization.ts`

### Dependencies Added
- `zod@4.3.6` for request validation
