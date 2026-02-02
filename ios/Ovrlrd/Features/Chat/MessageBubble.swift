import MarkdownUI
import SwiftUI

struct MessageBubble: View {

    // MARK: - Public Properties

    let message: Message

    // MARK: - Body

    var body: some View {
        switch message.role {
        case .system:
            systemMessage
        case .user:
            userMessage
        case .assistant:
            assistantMessage
        }
    }

    // MARK: - Private Views

    private var systemMessage: some View {
        HStack {
            Spacer()
            Text(message.content)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var userMessage: some View {
        HStack {
            Spacer(minLength: 60)
            HStack(spacing: 8) {
                if message.sendFailed {
                    errorIndicator
                }
                bubbleContent(isUser: true)
            }
        }
    }

    private var assistantMessage: some View {
        HStack {
            bubbleContent(isUser: false)
            Spacer(minLength: 60)
        }
    }

    private func bubbleContent(isUser: Bool) -> some View {
        Markdown(message.content)
            .markdownTheme(isUser ? .userBubble : .assistantBubble)
            .padding(12)
            .background(isUser ? Color.blue : Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    UIPasteboard.general.string = message.content
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                if let date = DateParser.parse(message.createdAt) {
                    Text(DateParser.formatTimestamp(date))
                }
            }
    }

    private var errorIndicator: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .foregroundStyle(.red)
            .font(.title3)
    }
}

// MARK: - Markdown Themes

extension Theme {
    @MainActor
    static var userBubble: Theme {
        Theme()
            .text {
                ForegroundColor(.white)
            }
            .code {
                FontFamilyVariant(.monospaced)
                ForegroundColor(Color.white.opacity(0.9))
                BackgroundColor(Color.white.opacity(0.2))
            }
            .strong {
                FontWeight(.bold)
            }
            .emphasis {
                FontStyle(.italic)
            }
            .link {
                ForegroundColor(.white)
                UnderlineStyle(.single)
            }
    }

    @MainActor
    static var assistantBubble: Theme {
        Theme()
            .code {
                FontFamilyVariant(.monospaced)
                BackgroundColor(Color(UIColor.systemGray4))
            }
            .link {
                ForegroundColor(.blue)
            }
    }
}

// MARK: - Previews

#Preview("User Message") {
    MessageBubble(message: .mockUserShort)
        .padding()
}

#Preview("Assistant Message") {
    MessageBubble(message: .mockAssistantShort)
        .padding()
}

#Preview("System Message - Approved") {
    MessageBubble(message: .mockSystemApproved)
        .padding()
}

#Preview("System Message - Denied") {
    MessageBubble(message: .mockSystemDenied)
        .padding()
}

#Preview("Failed Message") {
    MessageBubble(message: .mockUserFailed)
        .padding()
}

#Preview("Long Messages") {
    ScrollView {
        VStack(spacing: 16) {
            MessageBubble(message: .mockUserLong)
            MessageBubble(message: .mockAssistantLong)
        }
        .padding()
    }
}

#Preview("Code Block") {
    ScrollView {
        VStack(spacing: 16) {
            MessageBubble(message: .mockUserCode)
            MessageBubble(message: .mockAssistantCode)
        }
        .padding()
    }
}

#Preview("Full Conversation") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(Message.mockConversation) { message in
                MessageBubble(message: message)
            }
        }
        .padding()
    }
}
