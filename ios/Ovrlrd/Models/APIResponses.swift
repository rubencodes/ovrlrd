import Foundation

struct AuthResponse: Codable {
    let sessionToken: String
    let userId: String
    let expiresIn: Int // seconds until token expires
}

struct ConversationsResponse: Codable {
    let conversations: [Conversation]
    let hasMore: Bool?
    let nextCursor: String?
}

struct MessagesResponse: Codable {
    let conversation: Conversation
    let messages: [Message]
    let hasMore: Bool?
    let nextCursor: String?
}

// MARK: - Mock Data

extension AuthResponse {
    static let mock = AuthResponse(
        sessionToken: "mock-session-token-12345",
        userId: "user-1",
        expiresIn: 86400 // 24 hours
    )
}

extension ConversationsResponse {
    static let mock = ConversationsResponse(
        conversations: Conversation.mockList,
        hasMore: false,
        nextCursor: nil
    )

    static let mockEmpty = ConversationsResponse(
        conversations: [],
        hasMore: false,
        nextCursor: nil
    )
}

extension MessagesResponse {
    static let mock = MessagesResponse(
        conversation: .mockToday,
        messages: Message.mockConversation,
        hasMore: false,
        nextCursor: nil
    )

    static let mockEmpty = MessagesResponse(
        conversation: .mockToday,
        messages: [],
        hasMore: false,
        nextCursor: nil
    )
}
