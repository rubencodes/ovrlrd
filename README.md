# Ovrlrd

A native iOS interface for Claude CLI that preserves the full power of Claude Code—tools, skills, session memory, and MCP servers—accessible from your phone.

## Why

Claude CLI is powerful. It can read files, run commands, use tools, maintain conversation context across sessions, and integrate with MCP servers. But it's tied to your terminal.

Ovrlrd bridges that gap. It's not a simplified mobile chatbot—it's a direct line to your Claude CLI instance running on your local machine. When you send a message from your phone, it reaches the same Claude session that has access to your filesystem, your tools, and your project context.

## How It Works

```
┌─────────────────┐                    ┌─────────────────┐                    ┌─────────────────┐
│   iOS Client    │ ◄───────────────►  │  Local Server   │ ◄───────────────►  │   Claude CLI    │
│   (SwiftUI)     │       HTTPS        │   (Bun/Hono)    │    subprocess      │   (session-id)  │
└─────────────────┘                    └─────────────────┘                    └─────────────────┘
```

### The Server

A lightweight Bun/Hono server that:

- **Manages Claude CLI sessions**: Each conversation maps to a persistent Claude session via `--resume`. Your conversation history, tool approvals, and context carry across messages.
- **Streams responses**: Uses Claude CLI's streaming JSON output to deliver responses token-by-token via Server-Sent Events.
- **Handles authentication**: Apple Sign In with an allowlist of approved users/devices. Your Claude instance, your rules.
- **Stores conversations**: SQLite database for messages and conversation metadata. The actual Claude context lives in Claude's session files.
- **Production-ready security**: API key authentication, rate limiting, request validation, CORS configuration, and audit logging.

### The iOS App

A native SwiftUI app that:

- **Renders Claude's responses**: Full markdown support including code blocks, tables, and formatting.
- **Handles tool permissions**: When Claude wants to run a command or access a file, you see the same permission prompt you'd see in the terminal—approve or deny from your phone.
- **Manages conversations**: Create, browse, pin, and delete conversations. Titles auto-generate from the first message.
- **Streams in real-time**: Watch Claude think and respond, just like in the terminal.

## What You Get

- **Full Claude CLI capabilities from mobile**: Tools, skills, MCP servers, file access—everything Claude CLI can do.
- **Persistent sessions**: Resume conversations exactly where you left off, with full context.
- **Permission control**: Approve or deny tool usage on a per-request basis.
- **Private by design**: Runs on your machine, your network. No third-party services required.

## Architecture

The key insight is that we don't try to recreate Claude's capabilities—we just proxy to Claude CLI. This means:

1. **No capability drift**: As Claude CLI gains new features, Ovrlrd gets them automatically.
2. **Full context**: Claude sees your actual files, can run actual commands, uses your actual MCP servers.
3. **Session continuity**: The `--resume` flag preserves everything across messages.

The server acts as a thin translation layer:
- Converts HTTP requests to CLI invocations
- Parses streaming JSON output into SSE events
- Maps permission requests to a mobile-friendly approval flow

### Streaming & Tool Use

Responses stream via Server-Sent Events. When Claude uses tools mid-response, the text naturally splits into separate messages:

1. Claude sends text: "Let me check that file..."
2. Server sends `segment_end` → first message is finalized
3. Server sends `tool_start` → client shows "working" indicator with tool name
4. Tool executes
5. Server sends `tool_end`
6. Claude resumes with new text → becomes a new message

This creates a natural conversation flow where each thought and action is its own message, avoiding awkward spacing when text resumes after tool use

## Future Work

The current setup requires the iOS app to reach the local server. Options for remote access include:

- **Tunneling**: Tools like ngrok or Cloudflare Tunnel can expose the local server
- **Tailscale/ZeroTier**: Private networking without public exposure
- **Push notifications**: For long-running requests when the app is backgrounded

## Project Structure

```
ovrlrd/
├── server/    # Bun/Hono backend (see server/README.md)
└── ios/       # SwiftUI client (see ios/README.md)
```

## Getting Started

### Prerequisites

**Required tools:**

```bash
# Claude CLI
npm install -g @anthropic-ai/claude-cli
claude login

# Bun runtime
curl -fsSL https://bun.sh/install | bash

# XcodeGen (for iOS)
brew install xcodegen
```

**Also required:**
- macOS (for running the server and Xcode)
- Xcode 16+ (for iOS development)
- Apple Developer account (for running on device - Sign In with Apple requires it)

### Server Setup

```bash
cd server
bun install
cp .env.example .env
```

Edit `.env` with your settings:
```bash
# Required - generate with: openssl rand -base64 32
JWT_SECRET=your-random-secret
API_KEY=your-api-key

# User allowlist
APPROVED_EMAILS=you@example.com
```

Start the server:
```bash
bun run dev
```

### iOS Setup

```bash
cd ios
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Edit `Config/Local.xcconfig` with your Apple Developer Team ID:
```
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

Generate and open the project:
```bash
xcodegen generate
open Ovrlrd.xcodeproj
```

Build and run on a physical device (Sign In with Apple requires it).

On first launch, the app will prompt you to enter your server URL and API key—no rebuild required when these change.

### Local Development

To run the full stack locally:

1. **Start the server:**
   ```bash
   cd server && bun run dev
   ```

2. **Expose via ngrok** (needed for HTTPS and Sign In with Apple):
   ```bash
   ngrok http 3000
   ```

3. **Build and run the iOS app** on a physical device

4. **Enter your server URL** in the app's onboarding screen (e.g., `https://your-subdomain.ngrok-free.app`)

When the ngrok URL changes, just update it in the app's settings (tap the server indicator in the toolbar)—no rebuild needed.
