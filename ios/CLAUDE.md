# iOS CLAUDE.md

Project-specific guidance for Claude Code when working on the Ovrlrd iOS app.

## Quick Start

```bash
cd ios
xcodegen generate        # Regenerate Xcode project
open Ovrlrd.xcodeproj    # Open in Xcode
```

Build and run on a physical device (Sign In with Apple requires device).

## Build Verification

**IMPORTANT:** Always build the project after making Swift changes to verify there are no compilation errors. Swift's strict type system and concurrency checking can catch issues that aren't visible until compile time.

```bash
# Quick build check (from ios/ directory)
xcodebuild -scheme Ovrlrd -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "(error:|warning:|BUILD)"
```

Run this before considering any Swift changes complete. Fix all errors and review warnings.

## Architecture

SwiftUI app using `@Observable` pattern (iOS 17+) with clear separation:

```
Ovrlrd/
├── App/           # Entry point, AppDelegate
├── Extensions/    # Swift type extensions (URL+, String+, etc.)
├── Features/      # Views organized by feature
├── Models/        # Data types (Conversation, Message, APIResponses)
├── ViewModels/    # @Observable state management
└── Services/      # Network, auth, utilities
```

### File Organization Principles
- **One file = one concept**: Each file should contain a single type or closely related types
- **Extensions in Extensions/**: Type extensions go in `Extensions/TypeName+Feature.swift`
- **No utility grab-bags**: Avoid files like `Helpers.swift` or `Utils.swift`

### Key Files

| File | Purpose |
|------|---------|
| `Services/APIClient.swift` | All REST API calls |
| `Services/SSEService.swift` | Server-Sent Events for streaming |
| `Services/AuthService.swift` | Authentication state |
| `ViewModels/ChatViewModel.swift` | Chat state, SSE handling, permissions |
| `Features/Chat/ChatView.swift` | Main chat UI |

## Code Style

### MARK Pragmas
Use `// MARK: - Section Name` to organize code. Standard sections in order:

**Views:**
```swift
// MARK: - Environment
// MARK: - State
// MARK: - Public Properties
// MARK: - Private Properties
// MARK: - Initialization
// MARK: - Body
// MARK: - Private Views
// MARK: - Private Methods
```

**ViewModifiers:**
```swift
// MARK: - View Modifier
// MARK: - Public Properties
// MARK: - Private State
// MARK: - Body
// MARK: - View Extension
```

**ViewModels:**
```swift
// MARK: - Public Properties
// MARK: - Private Properties
// MARK: - Types
// MARK: - Initialization
// MARK: - Public Methods
// MARK: - Private Methods
```

**At file level** (outside types):
```swift
// MARK: - Previews
// MARK: - Notification Names
```

### Naming
- Views: `FooView.swift`, `FooSheet.swift`, `FooRow.swift`
- ViewModels: `FooViewModel.swift`
- View Modifiers: `FooModifier.swift`
- Services: `FooService.swift`

## Patterns

### State Management
- Use `@Observable` classes (not `ObservableObject`)
- Mark observable classes with `@MainActor`
- Use `@State` for view-local state, `private(set)` for ViewModel properties
- Services injected via `@Environment`

### State Enums for Multi-State UI
When a view or component has multiple mutually exclusive states (loading, error, success, empty, etc.), use a state enum instead of multiple boolean flags. This prevents invalid state combinations and makes the code self-documenting.

```swift
// ✅ Preferred: State enum
enum ViewState {
    case loading
    case empty
    case loaded([Item])
    case error(String)
}

@State private var state: ViewState = .loading

var body: some View {
    switch state {
    case .loading:
        ProgressView()
    case .empty:
        ContentUnavailableView("No Items", systemImage: "tray")
    case .loaded(let items):
        List(items) { ... }
    case .error(let message):
        ErrorView(message: message)
    }
}

// ❌ Avoid: Multiple booleans (allows invalid combinations)
@State private var isLoading = false
@State private var hasError = false
@State private var isEmpty = false
// What if isLoading && hasError are both true?
```

Use state enums for:
- App launch flows (loading → onboarding → auth → main)
- Data fetching (idle → loading → success/error)
- Form submission (editing → submitting → success/error)
- Multi-step wizards

### Error Handling
- Global `ErrorService` via `@Environment(\.errorService)`
- Show errors: `errorService.show("Message")` or `errorService.show(error)`
- Auto-dismisses after 5 seconds

### Constants
- Use `AppConstants` enum for magic numbers (timeouts, limits, thresholds)
- Group related constants with `// MARK: -` sections
- Add doc comments explaining the value's purpose

### Centralized Metadata
- `ToolMetadata` provides display names and SF Symbols for Claude tools
- Add new tools to both `activityDescription(for:)` and `icon(for:)` methods

### Animations
- Use `.snappy` for quick interactions (list reordering, title updates)
- Use `.spring(duration:bounce:)` for bouncy pop-in effects
- Abstract reusable animations into view modifiers (e.g., `.popIn()`)
- Prefer `.contentTransition(.numericText())` for text changes in lists

### Haptic Feedback
- Use `.sensoryFeedback()` modifier for user interactions
- Example: `.sensoryFeedback(.impact(flexibility: .solid, intensity: 0.7), trigger: value)`

### Cross-Component Communication
- Use Combine publishers for `NotificationCenter` subscriptions (not `addObserver`)
- Store subscriptions in `@ObservationIgnored private var cancellables = Set<AnyCancellable>()`
- Combine handles automatic cleanup on deallocation (no manual `removeObserver` needed)
- Define notification names as extensions on `Notification.Name`

```swift
// ✅ Preferred: Combine publisher
NotificationCenter.default.publisher(for: .conversationTitleUpdated)
    .receive(on: DispatchQueue.main)
    .sink { [weak self] notification in
        // Handle notification
    }
    .store(in: &cancellables)

// ❌ Avoid: addObserver pattern (requires manual cleanup)
NotificationCenter.default.addObserver(forName: ...) { ... }
```

### Custom View Modifiers
- Create modifiers for reusable behavior: `.popIn()`, `.withErrorBanner()`
- Place in `Features/Common/` directory
- Follow the ViewModifier MARK structure

### Previews
- Each view has `#Preview` blocks with mock data
- Mock data defined as static properties on model types in `// MARK: - Mock Data` extension
- Use `@Previewable` for state in previews
- Create multiple previews for different states (empty, loading, with data, error)

### SSE Streaming
The app uses Server-Sent Events for real-time responses:

1. `SSEService.sendAndStream()` opens connection
2. Events parsed and forwarded to `ChatViewModel.handleSSEEvent()`
3. Terminal events (`complete`, `error`, `permissionRequired`, `noResponse`) auto-disconnect

### Permission Flow
When Claude needs tool approval:
1. Server sends `permission_required` with `denials` array
2. `ChatViewModel` stores as `pendingPermissionRequest`
3. `PermissionApprovalSheet` presents approval UI
4. On approve: `retryWithApprovedTools()` resends with `allowedTools`

## Common Changes

### Adding an API endpoint
1. Add method to `Services/APIClient.swift`
2. Add response type to `Models/APIResponses.swift` if needed
3. Call from ViewModel or View

### Adding a new SSE event type
1. Add case to `SSEEventType` enum in `SSEService.swift`
2. Add handling in `ChatViewModel.handleSSEEvent()`
3. Add to disconnect conditions if it's a terminal event

### Adding a new View
1. Create in appropriate `Features/` subdirectory
2. Add MARK pragmas following the standard order
3. Add `#Preview` with mock data
4. Run `xcodegen generate` to add to project

### Adding a View Modifier
1. Create `FooModifier.swift` in `Features/Common/`
2. Implement `ViewModifier` protocol with MARK sections
3. Add `View` extension with convenience method (e.g., `.foo()`)
4. Run `xcodegen generate` to add to project

### Adding a Constant
1. Add to appropriate section in `Services/AppConstants.swift`
2. Use descriptive name and add doc comment
3. Reference as `AppConstants.fooBar` throughout codebase

### Adding a Type Extension
1. Create `TypeName+Feature.swift` in `Extensions/` (e.g., `URL+Normalized.swift`)
2. Keep extensions focused on a single capability
3. Add doc comments for public methods
4. Run `xcodegen generate` to add to project

## Configuration

### Build Configuration
Edit `Config/Local.xcconfig`:
- `DEVELOPMENT_TEAM`: Your Apple Developer Team ID

Run `xcodegen generate` after changes.

### Server Configuration
Server URL and API key are configured at runtime via the app's onboarding flow:
1. On first launch, `ServerOnboardingView` prompts for server details
2. Configuration stored in `UserDefaults` (URL) and `Keychain` (API key)
3. `ServerConfigService` manages the configuration and health checks
4. Users can modify settings via `ServerSettingsSheet` from the toolbar

## Dependencies

- **MarkdownUI** - Renders markdown in message bubbles (use `.markdownTheme(.assistantBubble)`)
- **XcodeGen** - Project generation from `project.yml`
- Requires iOS 26+
