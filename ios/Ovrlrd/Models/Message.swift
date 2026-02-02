import Foundation

struct Message: Identifiable, Codable {
    let id: String
    let conversationId: String
    let role: MessageRole
    let content: String
    let createdAt: String

    // Local-only state (not encoded/decoded)
    var sendFailed: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, conversationId, role, content, createdAt
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

// MARK: - Mock Data

extension Message {
    static let mockUserShort = Message(
        id: "msg-1",
        conversationId: "conv-1",
        role: .user,
        content: "Hello, can you help me with Swift?",
        createdAt: "2026-01-30 14:30:00"
    )

    static let mockAssistantShort = Message(
        id: "msg-2",
        conversationId: "conv-1",
        role: .assistant,
        content: "Of course! I'd be happy to help you with Swift. What would you like to know?",
        createdAt: "2026-01-30 14:30:15"
    )

    static let mockUserLong = Message(
        id: "msg-3",
        conversationId: "conv-1",
        role: .user,
        content: "I'm trying to understand the difference between structs and classes in Swift. When should I use one over the other? I've read that structs are value types and classes are reference types, but I'm not sure what that means in practice.",
        createdAt: "2026-01-30 14:31:00"
    )

    static let mockAssistantLong = Message(
        id: "msg-4",
        conversationId: "conv-1",
        role: .assistant,
        content: """
        Great question! Here's a breakdown of the key differences:

        **Value Types (Structs)**
        - Copied when assigned or passed to functions
        - Each copy is independent
        - Thread-safe by default
        - Stored on the stack (usually faster)

        **Reference Types (Classes)**
        - Share the same instance when assigned
        - Changes affect all references
        - Support inheritance
        - Have deinitializers

        **When to use Structs:**
        - Simple data containers
        - When you want copies to be independent
        - Most of your custom types

        **When to use Classes:**
        - When you need inheritance
        - When identity matters (e.g., managing a resource)
        - When you need to share mutable state

        Apple recommends starting with structs and only using classes when you specifically need their features.
        """,
        createdAt: "2026-01-30 14:31:30"
    )

    static let mockConversation: [Message] = [
        mockUserShort,
        mockAssistantShort,
        mockUserLong,
        mockAssistantLong
    ]

    static let mockUserCode = Message(
        id: "msg-5",
        conversationId: "conv-1",
        role: .user,
        content: "Can you show me an example?",
        createdAt: "2026-01-30 14:32:00"
    )

    static let mockAssistantCode = Message(
        id: "msg-6",
        conversationId: "conv-1",
        role: .assistant,
        content: """
        Here's a simple example:

        ```swift
        // Struct (Value Type)
        struct Point {
            var x: Int
            var y: Int
        }

        var p1 = Point(x: 0, y: 0)
        var p2 = p1  // Creates a copy
        p2.x = 10
        print(p1.x)  // Still 0

        // Class (Reference Type)
        class Person {
            var name: String
            init(name: String) {
                self.name = name
            }
        }

        var person1 = Person(name: "Alice")
        var person2 = person1  // Same instance
        person2.name = "Bob"
        print(person1.name)  // Now "Bob"
        ```
        """,
        createdAt: "2026-01-30 14:32:30"
    )

    static var mockUserFailed: Message {
        var message = Message(
            id: "msg-failed",
            conversationId: "conv-1",
            role: .user,
            content: "This message failed to send",
            createdAt: "2026-01-30 14:33:00"
        )
        message.sendFailed = true
        return message
    }

    static let mockSystemApproved = Message(
        id: "msg-system-1",
        conversationId: "conv-1",
        role: .system,
        content: "✓ Approved: Write",
        createdAt: "2026-01-30 14:34:00"
    )

    static let mockSystemDenied = Message(
        id: "msg-system-2",
        conversationId: "conv-1",
        role: .system,
        content: "✗ Denied: Bash",
        createdAt: "2026-01-30 14:35:00"
    )
}
