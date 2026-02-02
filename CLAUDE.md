# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**ovrlrd** - Personal Claude assistant with iOS client and local server. Messages from the iOS app are routed to Claude CLI on the server, maintaining full session context (tools, skills, conversation history).

## Architecture

```
┌─────────────────┐       HTTPS        ┌─────────────────┐      --resume      ┌─────────────────┐
│   iOS Client    │ ◄───────────────►  │  Local Server   │ ◄───────────────►  │   Claude CLI    │
│   (SwiftUI)     │      (ngrok)       │   (Bun/Hono)    │    (session-id)    │   (subprocess)  │
└─────────────────┘                    └─────────────────┘                    └─────────────────┘
        │                                      │
   Sign In with Apple                    SQLite DB
   Push Notifications              (users, conversations,
                                    messages, sessions)
```

### Key Design Decisions

- **Session Management**: Each conversation maps to a Claude CLI session via `--resume <session-id>`. This preserves full context including tools, skills, and conversation history.
- **Streaming via SSE**: Responses stream to the iOS client via Server-Sent Events. When Claude uses tools mid-response, each text segment becomes a separate message (avoiding spacing issues when text resumes after tool use).
- **Push Notifications**: If user backgrounds app mid-request, server completes the request and sends APNs notification.

## Commands

### Server

```bash
cd server
bun install              # Install dependencies
bun run dev              # Start with hot reload
bun run start            # Start production
bun run typecheck        # Type check
```

**CRITICAL for Claude Code**: Always run the server from the `server/` directory. The server loads `.env` from the current working directory. Running from the wrong directory will:
- Create database files in the wrong location
- Fail to load environment configuration
- Cause data loss or corruption

```bash
# CORRECT - run from server directory
cd /Users/ruben/Developer/ovrlrd/server && ~/.bun/bin/bun --hot src/index.ts

# WRONG - do NOT run from other directories
~/.bun/bin/bun --hot /Users/ruben/Developer/ovrlrd/server/src/index.ts
```

### iOS

```bash
cd ios
xcodegen generate        # Regenerate Xcode project after adding/removing files
open Ovrlrd.xcodeproj    # Open in Xcode
```

### ngrok

```bash
ngrok http 3000          # Expose server publicly
```

## Configuration

### Server

Copy `server/.env.example` to `server/.env` and configure:

**Required in production:**
- `JWT_SECRET`: Random secret for session tokens (generate with `openssl rand -base64 32`)
- `API_KEY`: Pre-shared API key for client authentication (generate with `openssl rand -base64 32`)

**Recommended:**
- `APPROVED_EMAILS`: Comma-separated list of approved user emails
- `APPROVED_APPLE_IDS`: Comma-separated list of approved Apple user IDs
- `CORS_ORIGINS`: Comma-separated list of allowed CORS origins

**Optional:**
- `APPLE_TEAM_ID`: Your Apple Developer Team ID
- `APPLE_BUNDLE_ID`: iOS app bundle ID (default: `com.ovrlrd.app`)
- `APNS_KEY_ID` + `APNS_KEY_PATH`: For push notifications
- `LOG_PATH`: Debug log file location
- `DB_PATH`: SQLite database location
- `CLAUDE_WORK_DIR`: Working directory for Claude CLI (default: `$HOME`)
- `CLAUDE_ADDITIONAL_DIRS`: Colon-separated paths Claude can access (e.g., `/home/user/projects:/home/user/docs`)

**⚠️ Use absolute paths for `DB_PATH`, `LOG_PATH`, and `APNS_KEY_PATH`:**
```bash
# Good - works regardless of working directory
DB_PATH=/Users/ruben/Developer/ovrlrd/server/ovrlrd.db

# Bad - breaks if server started from wrong directory
DB_PATH=./ovrlrd.db
```
Relative paths resolve from the current working directory, not the server directory. If the server is started from a different location (e.g., project root, IDE, background process), a new database will be created in the wrong place and existing data will appear missing.

### iOS

1. Copy `ios/Config/Local.xcconfig.example` to `ios/Config/Local.xcconfig`
2. Set `DEVELOPMENT_TEAM` to your Apple Developer Team ID
3. Run `xcodegen generate` to regenerate the project

Server URL and API key are configured at runtime via the app's onboarding flow (not in xcconfig).

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/auth` | POST | Exchange Apple identity token + device token for session JWT |
| `/chat` | GET | List conversations (supports `limit`, `cursor` query params) |
| `/chat` | POST | Send message (creates new conversation) |
| `/chat/stream` | POST | Stream to new conversation (creates it) |
| `/chat/:id` | GET | Get conversation with messages (supports `limit`, `cursor`) |
| `/chat/:id` | POST | Send message to existing conversation |
| `/chat/:id` | DELETE | Delete a conversation |
| `/chat/:id/stream` | POST | Stream to existing conversation |
| `/chat/:id/events` | POST | Store a permission event (approval/denial) |
| `/health` | GET | Health check |

### SSE Events (`/chat/stream`, `/chat/:id/stream`)

| Event | Description |
|-------|-------------|
| `chunk` | Streaming text content |
| `segment_end` | Text segment complete (tool use starting) - client should finalize as message |
| `tool_start` | Claude started using a tool (includes `toolName`) |
| `tool_end` | Tool execution completed |
| `complete` | Request complete |
| `no_response` | Request completed but produced no visible output |
| `permission_required` | Tool needs user approval (includes `denials` array) |
| `error` | Error occurred |

## Project Structure

### Server (`server/`)

```
src/
├── app.ts                 # Hono app setup, middleware, error handler
├── config.ts              # Environment configuration with validation
├── index.ts               # Entry point
├── db/
│   ├── schema.ts          # SQLite schema, migrations, version tracking
│   ├── users.ts           # User queries
│   └── conversations.ts   # Conversation/message queries (with transactions)
├── middleware/
│   ├── auth.ts            # JWT verification middleware
│   ├── apiKey.ts          # API key verification
│   └── rateLimit.ts       # Rate limiting (standard, claude, auth)
├── routes/
│   ├── auth.ts            # POST /auth - Apple Sign In
│   └── chat.ts            # GET/POST /chat endpoints
├── services/
│   ├── apns.ts            # Apple Push Notifications (with retry)
│   ├── audit.ts           # Audit logging
│   ├── claude.ts          # Claude CLI subprocess (non-streaming)
│   ├── claude-config.ts   # Shared Claude CLI configuration
│   ├── claude-stream.ts   # Claude CLI with SSE streaming + tool events
│   └── logger.ts          # Synchronous file-based logging
├── utils/
│   ├── auth.ts            # Conversation authorization helper
│   └── request.ts         # IP/user-agent extraction
└── validation/
    └── schemas.ts         # Zod schemas for request validation
```

### iOS (`ios/`)

```
Ovrlrd/
├── App/
│   ├── OvrlrdApp.swift       # App entry, error banner setup
│   ├── AppDelegate.swift     # Push notification handling
│   └── Info.plist
├── Features/
│   ├── Auth/
│   │   └── AuthView.swift    # Sign In with Apple UI
│   ├── Chat/
│   │   ├── ChatListView.swift
│   │   ├── ChatView.swift
│   │   ├── ConversationRow.swift
│   │   ├── MessageBubble.swift
│   │   ├── MessageInputBar.swift
│   │   └── PermissionApprovalSheet.swift
│   └── Common/
│       └── ErrorBanner.swift  # Global error banner + modifier
├── Models/
│   ├── Conversation.swift    # + mock data
│   ├── Message.swift         # + mock data
│   └── APIResponses.swift    # Response types + mocks
├── ViewModels/
│   └── ChatViewModel.swift   # Chat state, SSE handling, tool events
└── Services/
    ├── APIClient.swift       # Network layer
    ├── AppConstants.swift    # App-wide constants (timeouts, limits)
    ├── AuthService.swift     # Auth state management
    ├── Config.swift          # API configuration (from xcconfig/Info.plist)
    ├── DateParser.swift      # ISO8601/SQLite date parsing
    ├── ErrorService.swift    # Global error state
    ├── KeychainService.swift # Secure token storage
    └── SSEService.swift      # Server-Sent Events client for streaming
```

## Server Patterns

### Request Validation
- All request bodies are validated using Zod schemas in `src/validation/schemas.ts`
- Use `parseBody(request, schema)` and `parseQuery(url, schema)` helpers
- Validation errors throw `ValidationError` which returns 400 with helpful message

### Database
- Migrations are versioned in `src/db/schema.ts` - add new migrations to the `migrations` array
- Multi-step operations use transactions (see `createMessage()` in `conversations.ts`)
- Automatic backup before running migrations

### Rate Limiting
- Three pre-configured limiters: `standardRateLimit`, `claudeRateLimit`, `authRateLimit`
- Applied in `app.ts` to specific route patterns
- In-memory store (for production with multiple instances, use Redis)

### Claude Subprocess
- Shared configuration in `src/services/claude-config.ts`
- 2-minute timeout on all subprocess operations
- Resources properly cleaned up (readers released, processes killed on error)

### Timeouts
| Component | Timeout | Reason |
|-----------|---------|--------|
| Server subprocess | 2 min | Prevent hung Claude processes |
| iOS SSE connection | 5 min | Allow time for permission approval flows |

iOS timeout is intentionally longer to handle cases where user takes time to approve/deny tool permissions.

### Authorization
- Use `authorizeConversation(c, conversationId)` helper from `src/utils/authorization.ts`
- Returns `{ authorized: true, conversation }` or `{ authorized: false, error, status }`

## iOS Patterns

### Previews
- Each view has `#Preview` blocks with mock data
- Views have preview initializers that accept pre-loaded data
- Use `@Previewable` for state in previews, not wrapper views
- Mock data defined as static properties on model types (e.g., `Message.mockConversation`)

### Error Handling
- Global `ErrorService` accessible via `@Environment(\.errorService)`
- Show errors: `errorService.show("Message")` or `errorService.show(error)`
- Auto-dismisses after 5 seconds, or manually via X button
- `.withErrorBanner()` modifier applied at app root

### Navigation
- `NavigationStack` with value-based navigation
- Deep linking via `NotificationCenter` for push notification taps

## Debugging

Server errors log to `server/debug.log`:
```bash
tail -f server/debug.log
```

Log format: `[timestamp] [LEVEL] [context] message`
