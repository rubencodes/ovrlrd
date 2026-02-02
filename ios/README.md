# Ovrlrd iOS

A native SwiftUI client for interacting with Claude CLI through the Ovrlrd server.

## What It Does

- **Native chat interface**: Send messages and receive streaming responses with full markdown rendering.
- **Tool permission handling**: When Claude needs to run a command or access a file, you see the permission request and can approve or deny.
- **Conversation management**: Browse, create, pin, and delete conversations.
- **Apple Sign In**: Secure authentication tied to your Apple ID.
- **Dynamic server configuration**: Configure your server URL and API key at runtime (no rebuild required).

## Requirements

- **iOS 26+** (uses latest SwiftUI APIs)
- **Xcode 16+**
- **Physical device** for Sign In with Apple (simulator requires additional configuration)

### Dependencies

- [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) - Markdown rendering in message bubbles

## Setup

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen):
   ```bash
   brew install xcodegen
   ```

2. Create your local config (gitignored):
   ```bash
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```

3. Edit `Config/Local.xcconfig` with your Apple Developer Team ID:
   ```
   DEVELOPMENT_TEAM = YOUR_TEAM_ID
   ```

4. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```

5. Open in Xcode:
   ```bash
   open Ovrlrd.xcodeproj
   ```

6. Build and run on a physical device (Sign In with Apple requires a real device).

7. On first launch, enter your server URL and optional API key in the onboarding sheet.

## Project Structure

```
Ovrlrd/
├── App/           # Entry point, AppDelegate
├── Extensions/    # Swift type extensions
├── Features/      # Views organized by feature (Auth, Chat, Common, Onboarding, Settings)
├── Models/        # Data types (Conversation, Message, APIResponses)
├── ViewModels/    # @Observable state management
└── Services/      # Networking, auth, storage, utilities
```

## Key Patterns

### Streaming

Messages use Server-Sent Events for real-time streaming. The `SSEService` handles the connection, and `ChatViewModel` accumulates chunks into the displayed response.

When Claude uses tools mid-response, the server sends `segment_end` to finalize the current text as a complete message, then `tool_start`/`tool_end` events bracket the tool execution. This results in multiple assistant messages for a single turn, creating a natural conversation flow. The UI shows a "working" indicator with the tool name during execution.

### Permission Flow

When Claude requests tool permission, the server sends a `permission_required` SSE event. The app shows a sheet with the tool details, and the user's choice is sent back with the next request via `allowedTools`.

### State Management

Views use `@Observable` view models. Auth state is global via `AuthService`. Errors surface through `ErrorService` which displays a dismissible banner with FIFO queuing for multiple errors.

### Server Configuration

Server URL and API key are configured dynamically at runtime:
- On first launch, `ServerOnboardingView` appears as a sheet prompting for server details
- Configuration is stored in `UserDefaults` (URL) and `Keychain` (API key)
- `ServerConfigService` manages configuration and performs health checks
- Users can view/modify settings via `ServerStatusIndicator` in the toolbar
- Deleting the configuration returns to the onboarding flow

### Pagination

Both conversation lists and message threads support infinite scroll with cursor-based pagination:

- **Conversations**: Automatically loads more when scrolling to the bottom of the list
- **Messages**: Shows "Load earlier messages" button at the top to fetch older messages

### Previews

Each view has `#Preview` blocks with mock data. Models define static mock instances (e.g., `Message.mockConversation`) for easy preview composition.
