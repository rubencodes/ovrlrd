# Ovrlrd Server

The backend service that bridges the iOS app to Claude CLI.

## What It Does

- **Proxies to Claude CLI**: Spawns Claude CLI as a subprocess with `--resume` for session persistence and `--output-format stream-json` for real-time streaming.
- **Manages sessions**: Maps conversations to Claude session IDs, preserving full context across messages.
- **Handles auth**: Verifies Apple Sign In tokens, maintains an allowlist of approved users.
- **Streams responses**: Parses Claude's JSON output and delivers it as Server-Sent Events.
- **Permission flow**: Surfaces Claude's tool permission requests so the iOS app can prompt the user.

## Setup

```bash
bun install
cp .env.example .env
```

Configure `.env` (see `.env.example` for full documentation).

## Environment Variables

### Server

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `NODE_ENV` | No | `development` | Set to `production` for production mode |
| `PORT` | No | `3000` | Server port |

### Security

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `JWT_SECRET` | **Production** | `dev-secret...` | JWT signing secret. Generate with `openssl rand -base64 32` |
| `API_KEY` | **Production** | - | Pre-shared API key for client auth. Generate with `openssl rand -base64 32` |
| `CORS_ORIGINS` | No | - | Comma-separated allowed origins. Empty = reject all cross-origin in production |

### User Allowlist

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `APPROVED_EMAILS` | Recommended | - | Comma-separated approved email addresses (case-insensitive) |
| `APPROVED_APPLE_IDS` | No | - | Comma-separated approved Apple user IDs (alternative to email) |

### Apple Configuration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `APPLE_TEAM_ID` | No | - | Apple Developer Team ID |
| `APPLE_BUNDLE_ID` | No | `com.ovrlrd.app` | iOS app bundle identifier |
| `APNS_KEY_ID` | No | - | APNs authentication key ID (for push notifications) |
| `APNS_KEY_PATH` | No | `./apns-key.p8` | Path to APNs `.p8` key file |

### Paths

> **Note:** Use absolute paths to avoid issues when server is started from different directories.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DB_PATH` | No | `./ovrlrd.db` | SQLite database file path |
| `LOG_PATH` | No | `./debug.log` | Debug log file path |
| `CLAUDE_PATH` | No | `claude` | Path to Claude CLI executable |

### Claude CLI Settings

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CLAUDE_WORK_DIR` | No | `$HOME` | Working directory for Claude CLI subprocess |
| `CLAUDE_ADDITIONAL_DIRS` | No | - | Colon-separated paths Claude can access (passed as `--add-dir` flags) |

**Example:**
```bash
CLAUDE_WORK_DIR=/Users/yourname
CLAUDE_ADDITIONAL_DIRS=/Users/yourname/Developer:/Users/yourname/Projects
```

### Debugging

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DEBUG` | No | - | Set to `1` to enable debug-level logging |

## Running

```bash
bun run dev       # Development with hot reload
bun run start     # Production
bun run typecheck # Type check
```

## Security Features

The server includes several production-ready security features:

| Feature | Description |
|---------|-------------|
| **API Key** | Pre-shared secret required for all requests (except `/health`) |
| **JWT Auth** | 24-hour tokens with 4-hour refresh grace period |
| **Rate Limiting** | Per-user limits: 30/min standard, 10/min Claude, 10/15min auth |
| **CORS** | Configurable origins, rejects all in production if not configured |
| **Input Validation** | Zod schemas validate all request bodies |
| **Audit Logging** | Security events logged to database |

### Rate Limits

| Endpoint Pattern | Limit | Window |
|------------------|-------|--------|
| `/auth/*` | 10 requests | 15 minutes |
| `/chat` | 30 requests | 1 minute |
| `/chat/stream`, `/chat/:id/stream` | 10 requests | 1 minute |

## API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/auth` | POST | Exchange Apple identity token for session JWT |
| `/chat` | GET | List conversations |
| `/chat` | POST | Send message (creates new conversation) |
| `/chat/stream` | POST | Stream to new conversation (creates it) |
| `/chat/:id` | GET | Get conversation with messages |
| `/chat/:id` | POST | Send message to existing conversation |
| `/chat/:id` | DELETE | Delete a conversation |
| `/chat/:id/stream` | POST | Stream to existing conversation |
| `/chat/:id/events` | POST | Store a permission event (approval/denial) |
| `/health` | GET | Health check (no auth required) |

### Pagination

Both list endpoints support cursor-based pagination:

```
GET /chat?limit=20&cursor=2025-01-30T12:00:00Z
GET /chat/:id?limit=50&cursor=2025-01-30T12:00:00Z
```

Response includes pagination metadata:
```json
{
  "conversations": [...],
  "hasMore": true,
  "nextCursor": "2025-01-29T18:30:00Z"
}
```

### Request Validation

All endpoints validate request bodies. Invalid requests return 400 with error details:

```json
{
  "error": "Message is required"
}
```

| Endpoint | Validation |
|----------|------------|
| `POST /auth` | `identityToken` required |
| `POST /chat`, `POST /chat/:id` | `message` required, max 100KB |
| `POST /chat/stream`, `POST /chat/:id/stream` | `message` required, `allowedTools` optional array |
| `POST /chat/:id/events` | `content` required, `role` optional (default: system) |

## How Claude Integration Works

1. User sends a message via `/chat/stream`
2. Server spawns: `claude -p --resume <session-id> --output-format stream-json`
3. Message is written to stdin
4. Claude's stdout is parsed line-by-line for JSON events
5. Events are forwarded to the client as SSE:
   - `chunk`: Streaming text content
   - `segment_end`: Text segment complete (tool use starting)
   - `tool_start`: Claude started using a tool
   - `tool_end`: Tool execution completed
   - `complete`: Request finished
   - `no_response`: Request completed but produced no visible output
   - `permission_required`: Claude needs tool approval
   - `error`: Something went wrong

### Subprocess Management

- **Timeout**: 2-minute timeout on all Claude operations
- **Cleanup**: Processes killed on error, readers properly released
- **Session tracking**: Active sessions tracked to prevent orphaned processes

### Multi-Message Responses

When Claude uses tools mid-response, the text is split into separate messages:

1. Claude sends text: "Let me check that file..."
2. Claude uses a tool (Read, Bash, etc.)
3. Server sends `segment_end` to finalize the first message
4. Server sends `tool_start` so client can show a working indicator
5. Tool executes
6. Server sends `tool_end`
7. Claude resumes with new text → new message

This prevents spacing issues when text resumes after tool use and creates a more natural conversation flow.

## Database

SQLite with WAL mode for better concurrency.

### Migrations

Migrations are versioned and tracked in a `migrations` table:

| Version | Name | Description |
|---------|------|-------------|
| 1 | initial_schema | Users, conversations, messages tables |
| 2 | add_pagination_indexes | Composite indexes for efficient pagination |
| 3 | add_audit_log_table | Audit logging with indexes |

Migrations run automatically on startup. A backup is created before any migration.

### Schema

```
users
├── id (PK)
├── apple_user_id (unique)
├── email
├── device_token
├── created_at
└── updated_at

conversations
├── id (PK)
├── user_id (FK → users)
├── claude_session_id
├── title
├── created_at
└── updated_at

messages
├── id (PK)
├── conversation_id (FK → conversations)
├── role (user | assistant | system)
├── content
└── created_at

audit_log
├── id (PK, auto-increment)
├── user_id
├── action
├── resource
├── resource_id
├── metadata (JSON)
├── ip
├── user_agent
└── created_at
```

## Project Structure

```
src/
├── app.ts                 # Hono app setup, middleware, error handler
├── config.ts              # Environment configuration with validation
├── index.ts               # Entry point, graceful shutdown
├── db/                    # Database layer
├── middleware/            # Auth, API key, rate limiting
├── routes/                # HTTP endpoints (auth, chat)
├── services/              # Claude CLI, push notifications, logging
├── utils/                 # Authorization, request helpers
└── validation/            # Zod request schemas
```

## Debugging

Server logs to `debug.log` (configurable via `LOG_PATH`):

```bash
tail -f debug.log
```

Log format: `[timestamp] [LEVEL] [context] message`

Levels: `ERROR`, `INFO`, `DEBUG` (DEBUG requires `DEBUG=1` env var)
