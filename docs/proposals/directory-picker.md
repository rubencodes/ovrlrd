# Feature Proposal: Directory Picker for Conversations

**Status:** Draft
**Created:** 2026-02-04

## Summary

Allow users to select a working directory when starting a new conversation. The system remembers frequently used directories and suggests them. Chats are grouped by directory in the list view.

## Motivation

Currently, all Claude CLI subprocesses spawn in a single configured directory (`CLAUDE_WORK_DIR`). Users working across multiple projects must manually navigate or lack context about which project a conversation relates to.

## Current State

- Server uses single `CLAUDE_WORK_DIR` env var for all conversations
- `CLAUDE_ADDITIONAL_DIRS` exists but only grants Claude access—doesn't let users choose
- No directory metadata stored on conversations
- iOS has no concept of working directory

## Proposed Design

### Database Schema Changes

**Migration 1: Add work_dir to conversations**
```sql
ALTER TABLE conversations ADD COLUMN work_dir TEXT;
CREATE INDEX idx_conversations_work_dir ON conversations(user_id, work_dir);
```

**Migration 2: Track directory usage**
```sql
CREATE TABLE user_directories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  path TEXT NOT NULL,
  label TEXT,
  access_count INTEGER DEFAULT 1,
  last_used TEXT DEFAULT (datetime('now')),
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX idx_user_directories_path ON user_directories(user_id, path);
CREATE INDEX idx_user_directories_last_used ON user_directories(user_id, last_used DESC);
```

### API Changes

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/chat` | POST | Add optional `workDir` field |
| `/chat/stream` | POST | Add optional `workDir` field |
| `/chat/directories` | GET | List user's directories (recent + configured) |
| `/chat/directories/:path/label` | POST | Update directory display label |
| `/chat/directories/:path` | DELETE | Remove from history |

### Server Changes

**Files to modify:**
- `src/db/schema.ts` - Add migrations
- `src/db/conversations.ts` - Add `workDir` to conversation creation, add directory tracking functions
- `src/db/directories.ts` (new) - Directory management queries
- `src/validation/schemas.ts` - Add `workDir` to chat schemas
- `src/routes/chat.ts` - Update endpoints, add directory routes
- `src/services/claude.ts` - Pass `workDir` to subprocess `cwd`
- `src/services/claude-stream.ts` - Pass `workDir` to subprocess `cwd`

**Claude spawn modification:**
```typescript
const proc = Bun.spawn([getClaudePath(), ...args], {
  cwd: workDir || getWorkDir(),  // Use provided workDir or fall back to config
  // ...
});
```

### iOS Changes

**Models:**
- `Conversation.swift` - Add `workDir: String?` property
- `APIResponses.swift` - Add `Directory` type

**New Views:**
- `DirectoryPickerView.swift` - Sheet for selecting directory when starting chat
- `DirectoryHeader.swift` - Section header showing directory name/path

**Modified Views:**
- `ChatListView.swift` - Add directory picker trigger, group conversations by directory
- `ConversationRow.swift` - Show directory indicator
- `ChatViewModel.swift` - Track and pass `workDir` when sending messages

**Services:**
- `APIClient.swift` - Add directory API methods, update message methods with `workDir`
- `SSEService.swift` - Pass `workDir` in stream requests

### UI Flow

1. User taps "+" to start new conversation
2. Menu appears: "Quick Chat" (default dir) or "Choose Directory"
3. If "Choose Directory" → DirectoryPickerView sheet
4. Sheet shows recent directories + configured directories from server
5. User selects or enters custom path
6. New conversation created with that `workDir`
7. Chat list groups conversations by directory with collapsible sections

### Grouping Display

```
┌─────────────────────────────────┐
│ 📁 ovrlrd                       │
│   /Users/ruben/Developer/ovrlrd │
├─────────────────────────────────┤
│   Help with SwiftUI layouts     │
│   Fix streaming bug             │
├─────────────────────────────────┤
│ 📁 other-project                │
│   /Users/ruben/Developer/other  │
├─────────────────────────────────┤
│   API refactoring discussion    │
├─────────────────────────────────┤
│ 📁 Default Directory            │
├─────────────────────────────────┤
│   Quick question about git      │
└─────────────────────────────────┘
```

## Implementation Phases

### Phase 1: Server Foundation
- Database migrations
- Directory tracking in `conversations.ts` and new `directories.ts`
- Validation schemas
- Directory routes

### Phase 2: Server Integration
- Update chat creation routes
- Pass `workDir` to Claude subprocess
- Test directory tracking

### Phase 3: iOS Models & API
- Update `Conversation` model
- Add `Directory` types
- API client methods
- SSEService updates

### Phase 4: iOS UI - Directory Picker
- Create `DirectoryPickerView`
- Integrate into `ChatListView`
- Handle quick chat vs directory selection

### Phase 5: iOS UI - Grouping
- Implement grouped conversations logic
- Create `DirectoryHeader`
- Update list sections
- Directory indicator in rows

## Backward Compatibility

- Existing conversations have `workDir = NULL`
- Server falls back to config default when `workDir` is null
- iOS displays null-workDir conversations under "Default Directory" section

## Future Enhancements

- Custom directory labels
- Pin favorite directories
- Search/filter by directory
- Directory statistics (conversation count, activity)
- Path autocomplete in custom input
