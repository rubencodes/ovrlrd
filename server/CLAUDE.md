# Server CLAUDE.md

Project-specific guidance for Claude Code when working on the Ovrlrd server.

## Quick Start

**CRITICAL**: Always run the server from this directory (`server/`). The server loads `.env` from the current working directory.

```bash
# ALWAYS cd to server directory first
cd /Users/ruben/Developer/ovrlrd/server

# Install dependencies
bun install

# Start with hot reload
~/.bun/bin/bun --hot src/index.ts

# Or use npm scripts
bun run dev      # Development with hot reload
bun run start    # Production
bun run typecheck
```

**Warning:** Running the server from the wrong directory will create database files in unexpected locations and fail to load configuration. Never run the server using an absolute path to the script from a different working directory.

## Architecture

The server proxies requests to Claude CLI, managing sessions and streaming responses.

```
iOS App → Hono Server → Claude CLI subprocess
              ↓
         SQLite DB (users, conversations, messages)
```

### Key Files

| File | Purpose |
|------|---------|
| `src/index.ts` | Entry point |
| `src/app.ts` | Hono app setup, middleware, error handling |
| `src/config.ts` | Environment config with validation |
| `src/routes/chat.ts` | All `/chat` endpoints |
| `src/routes/auth.ts` | Authentication endpoint |
| `src/services/claude-stream.ts` | Claude subprocess with SSE streaming |
| `src/services/claude-config.ts` | Shared Claude spawn configuration |
| `src/db/schema.ts` | Database schema and migrations |
| `src/validation/schemas.ts` | Zod request validation |

## Claude Subprocess

### Configuration (`claude-config.ts`)
- **Timeout:** 2 minutes (prevents hung processes)
- **Working directory:** User's home directory
- **Additional dirs:** `/Users/ruben/Developer` for project access
- **Output format:** `stream-json` for real-time parsing

### Session Management (`claude-stream.ts`)
- Sessions tracked in `activeSessions` Map
- Each conversation has a `claudeSessionId` for `--resume`
- Resources cleaned up on error or completion (readers released, process killed)

### SSE Events
The streaming endpoint emits these events:

| Event | When | Payload |
|-------|------|---------|
| `chunk` | Text content | `{ type, content }` |
| `segment_end` | Text complete, tool starting | `{ type, conversationId, content }` |
| `tool_start` | Tool execution begins | `{ type, toolName }` |
| `tool_end` | Tool execution done | `{ type, toolName }` |
| `complete` | Request finished | `{ type, conversationId }` |
| `no_response` | Completed with no output | `{ type, conversationId, message }` |
| `permission_required` | Needs user approval | `{ type, conversationId, denials }` |
| `error` | Something failed | `{ type, message }` |

## Database

**⚠️ Always use absolute paths in `.env` for `DB_PATH`, `LOG_PATH`, and `APNS_KEY_PATH`.** Relative paths resolve from the current working directory, not the server directory. If the server is started from a different location, a new database will be created and existing data will appear missing.

### Schema (`db/schema.ts`)
SQLite with WAL mode. Tables: `users`, `conversations`, `messages`, `audit_log`, `migrations`.

### Migrations
Versioned migrations run automatically on startup:
1. `initial_schema` - Core tables
2. `add_pagination_indexes` - Composite indexes for efficient queries
3. `add_audit_log_table` - Security event logging

To add a migration:
1. Add to `migrations` array in `schema.ts`
2. Increment version number
3. Provide `up` function with SQL

Backup created automatically before any migration runs.

### Transactions
Multi-step operations (like `createMessage`) use transactions to prevent inconsistent state.

## Request Validation

All requests validated with Zod schemas (`validation/schemas.ts`):
- `authRequestSchema` - `/auth` POST
- `chatMessageSchema` - Message endpoints
- `chatStreamSchema` - Streaming with optional `allowedTools`
- `permissionEventSchema` - Permission events
- `paginationSchema` - Query params

Use `parseBody(request, schema)` and `parseQuery(url, schema)` helpers.

## Rate Limiting

Three tiers configured in `app.ts`:
- **Auth:** 10 requests / 15 minutes
- **Standard:** 30 requests / 1 minute
- **Claude:** 10 requests / 1 minute (streaming endpoints)

In-memory store - for multi-instance, replace with Redis.

## Common Changes

### Adding an endpoint
1. Add route in `src/routes/chat.ts` or create new route file
2. Add Zod schema in `src/validation/schemas.ts`
3. Use `authorizeConversation()` for conversation-specific routes
4. Document in README.md

### Adding a migration
1. Add to `migrations` array in `src/db/schema.ts`
2. Use transaction: `db.exec('BEGIN'); ... db.exec('COMMIT');`

### Debugging
```bash
tail -f debug.log
```
Log levels: ERROR, INFO, DEBUG (DEBUG requires `DEBUG=1`)
