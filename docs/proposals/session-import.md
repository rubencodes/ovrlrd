# Feature Proposal: Session Import from Local Machine

**Status:** Draft
**Created:** 2026-02-04

## Summary

Import messages from existing Claude CLI sessions into ovrlrd, given a session ID. This allows users to continue conversations started locally through the iOS app.

## Motivation

Users may have valuable conversation history in their local Claude CLI sessions that they want to access from mobile. Currently there's no way to bring those conversations into ovrlrd.

## Claude CLI Session Storage

### Directory Structure
```
~/.claude/projects/
└── -Users-ruben-Developer-ovrlrd-server/
    ├── sessions-index.json              # Session metadata index
    ├── 29eab637-d0dc-4c3e-afc9-2385257d7699.jsonl  # Session data
    └── [... more sessions ...]
```

### Session Index Format (`sessions-index.json`)
```json
{
  "version": 1,
  "entries": [
    {
      "sessionId": "29eab637-d0dc-4c3e-afc9-2385257d7699",
      "fullPath": "/Users/ruben/.claude/projects/.../29eab637-....jsonl",
      "fileMtime": 1769806876565,
      "firstPrompt": "Hey Claude, how's it hangin'?",
      "messageCount": 25,
      "created": "2026-01-30T18:34:49.464Z",
      "modified": "2026-01-30T21:01:16.536Z",
      "gitBranch": "",
      "projectPath": "/Users/ruben/Developer/ovrlrd/server",
      "isSidechain": false
    }
  ],
  "originalPath": "/Users/ruben/Developer/ovrlrd/server"
}
```

### Session Data Format (JSONL)

Each line is a JSON object. Relevant entry types:

**User Message:**
```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": "Hey Claude, how's it hangin'?"
  },
  "uuid": "21298246-7cfb-4063-b3fd-9e660a993ffb",
  "timestamp": "2026-01-30T18:34:49.464Z",
  "sessionId": "29eab637-d0dc-4c3e-afc9-2385257d7699"
}
```

**Assistant Message:**
```json
{
  "type": "assistant",
  "message": {
    "role": "assistant",
    "content": [
      { "type": "text", "text": "Hey! All good here..." },
      { "type": "tool_use", "name": "bash", "input": { "command": "ls" } }
    ]
  },
  "uuid": "f89af1ca-14e9-492e-a351-beb4fca2b43d",
  "timestamp": "2026-01-30T18:34:51.751Z"
}
```

## Proposed Design

### Database Schema

**New table for import metadata:**
```sql
CREATE TABLE imported_sessions (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  session_id TEXT NOT NULL,
  session_path TEXT NOT NULL,
  message_count INTEGER,
  original_created_at TEXT,
  imported_at TEXT DEFAULT (datetime('now'))
);

CREATE INDEX idx_imported_sessions_conversation ON imported_sessions(conversation_id);
```

### API Endpoint

**POST /chat/import**

Request:
```json
{
  "sessionId": "29eab637-d0dc-4c3e-afc9-2385257d7699",
  "sessionPath": "/Users/ruben/.claude/projects/.../29eab637-....jsonl"
}
```

Success Response (200):
```json
{
  "conversationId": "conv-uuid-123",
  "messageCount": 25,
  "title": "Generated title from first exchange"
}
```

Error Responses:
| Status | Reason |
|--------|--------|
| 400 | Invalid session ID format, malformed JSONL, no messages |
| 403 | Permission denied reading file |
| 404 | Session file not found |
| 500 | Database or processing error |

**Optional: GET /chat/import/available-sessions**

Returns list of discoverable sessions from `~/.claude/projects/`:
```json
{
  "sessions": [
    {
      "sessionId": "29eab637-...",
      "path": "/Users/ruben/.claude/projects/...",
      "firstPrompt": "Hey Claude...",
      "messageCount": 25,
      "created": "2026-01-30T18:34:49.464Z",
      "projectPath": "/Users/ruben/Developer/ovrlrd/server"
    }
  ]
}
```

### Server Implementation

**New service: `src/services/session-importer.ts`**

```typescript
interface ParsedMessage {
  role: 'user' | 'assistant';
  content: string;
  timestamp: string;
}

interface SessionImportResult {
  sessionId: string;
  projectPath: string;
  messageCount: number;
  messages: ParsedMessage[];
  createdAt: string;
  modifiedAt: string;
}

// Functions:
// - validateSessionExists(path): Check file exists and is readable
// - parseSessionJsonl(path): Stream-read JSONL, filter messages
// - extractMessages(entries): Filter user/assistant, extract content
// - formatMessageContent(message): Handle content blocks
```

**Content extraction logic:**
```typescript
function extractContent(message: ClaudeMessage): string {
  const content = message.content;

  if (typeof content === 'string') {
    return content;
  }

  if (Array.isArray(content)) {
    return content
      .map(block => {
        if (block.type === 'text') return block.text;
        if (block.type === 'tool_use') {
          return `[Tool Use: ${block.name}]\nInput: ${JSON.stringify(block.input)}`;
        }
        if (block.type === 'tool_result') {
          return `[Tool Result]\n${block.content}`;
        }
        return '';
      })
      .filter(Boolean)
      .join('\n');
  }

  return '';
}
```

**Database helper in `src/db/conversations.ts`:**
```typescript
async function importMessages(
  conversationId: string,
  messages: Array<{ role: string; content: string; createdAt: string }>
): Promise<void> {
  // Transaction-wrapped bulk insert
  // Preserves original timestamps
  // Updates conversation.updated_at to latest message
}
```

**Files to modify/create:**
- `src/db/schema.ts` - Add migration
- `src/db/conversations.ts` - Add `importMessages()`
- `src/services/session-importer.ts` (new) - JSONL parsing
- `src/validation/schemas.ts` - Add import request schema
- `src/routes/chat.ts` - Add `POST /chat/import`

### iOS Implementation

**New view: `SessionImportSheet.swift`**

```swift
@MainActor
@Observable
final class SessionImportViewModel {
  enum ImportState {
    case idle
    case loading
    case ready([AvailableSession])
    case importing(sessionId: String)
    case success(conversationId: String)
    case error(String)
  }

  var state: ImportState = .idle
  var selectedSessionId: String?

  func loadAvailableSessions() async { ... }
  func importSession(sessionId: String, path: String) async { ... }
}

struct SessionImportSheet: View {
  // Display available sessions
  // Selection and import button
  // Progress/error feedback
}
```

**Model types in `APIResponses.swift`:**
```swift
struct AvailableSession: Identifiable, Codable {
  let sessionId: String
  let path: String
  let firstPrompt: String
  let messageCount: Int
  let created: String
  let projectPath: String

  var id: String { sessionId }
}

struct SessionImportResponse: Codable {
  let conversationId: String
  let messageCount: Int
  let title: String?
}
```

**API client method:**
```swift
func importSession(sessionId: String, sessionPath: String) async throws -> SessionImportResponse
```

**ChatListView integration:**
- Add "Import Session" to toolbar menu
- Present `SessionImportSheet`
- Navigate to imported conversation on success

## Message Mapping

| Claude CLI | ovrlrd Database |
|-----------|-----------------|
| `message.role` | `role` column |
| `message.content` (string or array) | `content` column (extracted text) |
| `timestamp` (ISO 8601) | `created_at` (preserved) |
| `uuid` | Not stored (new UUID generated for DB) |

## Edge Cases

**Large sessions (1000+ messages):**
- Stream JSONL parsing to avoid memory issues
- Transaction-wrapped bulk insert

**Duplicate imports:**
- Allow initially (creates separate conversation)
- Could add deduplication check later if UX testing shows need

**Partial/corrupted files:**
- All-or-nothing import (transaction rollback on error)
- Clear error messages for malformed data

**Permission issues:**
- Validate file readable before parsing
- Return 403 with helpful message

## Implementation Phases

### Phase 1: Core Server
- Migration for `imported_sessions` table
- Session validation helper
- JSONL parser (`session-importer.ts`)
- Content extraction for all block types
- `importMessages()` database function
- `POST /chat/import` endpoint

### Phase 2: iOS
- `SessionImportSheet` view and view model
- Session discovery (parse sessions-index.json)
- `APIClient.importSession()` method
- Response types
- Integration into `ChatListView`

### Phase 3: Polish
- Test with large sessions
- Test with tool use content
- Test error scenarios
- Loading/progress indicators

### Phase 4: Optional Enhancements
- `GET /chat/import/available-sessions` for auto-discovery
- Session preview before import
- Batch import multiple sessions

## Security Considerations

- Only allow importing from user's own `~/.claude/projects`
- Validate session path doesn't escape expected directory
- Server must run as user with read access to Claude config

## Future Enhancements

- Session discovery UI (browse without manual path)
- Batch import multiple sessions
- Structured tool metadata storage
- Merge sessions into existing conversation
- Selective import (choose message range)
- Export ovrlrd conversations to Claude CLI format
- Bidirectional sync
