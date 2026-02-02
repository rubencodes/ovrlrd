import Foundation

/// Application-wide constants to avoid magic numbers scattered throughout the codebase
enum AppConstants {

    // MARK: - Network

    /// Timeout for SSE streaming requests (5 minutes to allow for long Claude responses)
    static let sseTimeoutSeconds: TimeInterval = 300

    /// Buffer time before token expiry to trigger refresh (5 minutes)
    static let tokenRefreshBufferSeconds: TimeInterval = 300

    // MARK: - UI

    /// Maximum number of lines for message input field
    static let messageInputMaxLines = 5

    /// Time gap (in seconds) before showing timestamp separator between messages (1 hour)
    static let messageTimestampGapSeconds: TimeInterval = 3600

    // MARK: - Text Limits

    /// Maximum characters to show in conversation title
    static let conversationTitleMaxLength = 50

    /// Maximum characters to show in tool command preview
    static let toolCommandPreviewMaxLength = 50
}
