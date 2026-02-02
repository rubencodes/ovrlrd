import Combine
import Foundation
import UIKit

@MainActor
@Observable
final class ChatViewModel {

    // MARK: - Public Properties

    private(set) var messages: [Message] = []
    private(set) var isLoading = false
    private(set) var isSending = false
    private(set) var isStreaming = false
    private(set) var streamingText = ""
    private(set) var isToolExecuting = false
    private(set) var currentToolName: String?
    private(set) var claudeSessionId: String?
    private(set) var isLoadingMore = false
    private(set) var hasMoreMessages = false
    private(set) var conversationTitle: String?

    /// Pending permission request that needs user approval
    /// Note: Not private(set) because sheet binding requires setter access
    var pendingPermissionRequest: PendingPermissionRequest?

    // MARK: - Private Properties

    private var currentConversationId: String?
    private let initialConversationId: String?
    private let errorService: ErrorService
    private let sseService = SSEService()
    private var nextMessageCursor: String?
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    // MARK: - Types

    struct PendingPermissionRequest: Identifiable {
        let id = UUID()
        let conversationId: String
        let originalMessage: String
        let denials: [PermissionDenial]
    }

    // MARK: - Initialization

    init(conversationId: String? = nil, errorService: ErrorService = .shared) {
        self.initialConversationId = conversationId
        self.currentConversationId = conversationId
        self.errorService = errorService
        setupNotificationObservers()
    }

    init(messages: [Message], isLoading: Bool = false, isSending: Bool = false) {
        self.messages = messages
        self.isLoading = isLoading
        self.isSending = isSending
        self.initialConversationId = nil
        self.errorService = .shared
        // Don't set up observers for preview instances
    }

    // MARK: - Public Methods

    func loadMessages() async {
        guard let conversationId = initialConversationId, messages.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await APIClient.shared.getMessages(conversationId: conversationId)
            messages = response.messages
            claudeSessionId = response.conversation.claudeSessionId
            hasMoreMessages = response.hasMore ?? false
            nextMessageCursor = response.nextCursor
        } catch {
            errorService.show("Failed to load messages: \(error.localizedDescription)")
        }
    }

    func loadMoreMessages() async {
        guard let conversationId = initialConversationId,
              hasMoreMessages,
              !isLoadingMore,
              let cursor = nextMessageCursor else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let response = try await APIClient.shared.getMessages(
                conversationId: conversationId,
                cursor: cursor
            )
            // Prepend older messages to the beginning
            messages.insert(contentsOf: response.messages, at: 0)
            hasMoreMessages = response.hasMore ?? false
            nextMessageCursor = response.nextCursor
        } catch {
            errorService.show("Failed to load more messages: \(error.localizedDescription)")
        }
    }

    func disconnectStream() {
        sseService.disconnect()
    }

    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }

        // Add user message optimistically
        let messageId = UUID().uuidString
        let userMessage = Message(
            id: messageId,
            conversationId: currentConversationId ?? "",
            role: .user,
            content: trimmed,
            createdAt: DateParser.format(Date())
        )
        messages.append(userMessage)

        await sendMessageStreaming(trimmed, messageId: messageId)
    }

    /// Approve a pending permission request
    func approvePermission() {
        guard let request = pendingPermissionRequest else { return }

        let approvedTools = request.denials.map(\.toolName)

        // Add approval message locally as system message (server will also persist it)
        let approvalMessage = Message(
            id: UUID().uuidString,
            conversationId: request.conversationId,
            role: .system,
            content: "✓ Approved: \(approvedTools.joined(separator: ", "))",
            createdAt: DateParser.format(Date())
        )
        messages.append(approvalMessage)

        // Store the original message before clearing the request
        let originalMessage = request.originalMessage
        let conversationId = request.conversationId

        // Clear the pending request
        pendingPermissionRequest = nil

        // Retry with approved tools using the original message
        Task {
            await retryWithApprovedTools(
                message: originalMessage,
                conversationId: conversationId,
                allowedTools: approvedTools
            )
        }
    }

    /// Deny a pending permission request
    func denyPermission() {
        guard let request = pendingPermissionRequest else { return }

        let deniedTools = request.denials.map(\.toolName)
        let content = "✗ Denied: \(deniedTools.joined(separator: ", "))"
        let conversationId = request.conversationId

        // Add a system message showing what was denied
        let denialMessage = Message(
            id: UUID().uuidString,
            conversationId: conversationId,
            role: .system,
            content: content,
            createdAt: DateParser.format(Date())
        )
        messages.append(denialMessage)

        // Persist the denial message to the server
        Task { [errorService] in
            do {
                try await APIClient.shared.storePermissionEvent(
                    conversationId: conversationId,
                    role: "system",
                    content: content
                )
            } catch {
                errorService.show("Failed to save denial: \(error.localizedDescription)")
            }
        }

        // Clear the pending request
        pendingPermissionRequest = nil

        isSending = false
    }

    // MARK: - Private Methods

    private func setupNotificationObservers() {
        // Listen for push notifications indicating a message is ready
        NotificationCenter.default.publisher(for: .conversationMessageReady)
            .compactMap { $0.userInfo?["conversationId"] as? String }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] conversationId in
                self?.handleMessageReadyNotification(conversationId: conversationId)
            }
            .store(in: &cancellables)

        // Refresh messages when app becomes active (e.g., returning from background)
        // This catches cases where a push notification arrived while backgrounded
        // and the user opened the app without tapping the notification
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleAppBecameActive()
            }
            .store(in: &cancellables)
    }

    private func handleMessageReadyNotification(conversationId: String) {
        // Only refresh if this is the conversation we're viewing
        guard conversationId == currentConversationId || conversationId == initialConversationId else {
            return
        }

        // Don't refresh if we're actively streaming (we already have the data)
        guard !isStreaming && !isSending else {
            return
        }

        // Refresh messages from the server
        Task {
            await refreshMessages()
        }
    }

    private func handleAppBecameActive() {
        // Don't refresh if we're actively sending/streaming (we have the latest data)
        guard !isStreaming && !isSending else {
            return
        }

        // Only refresh if we have a conversation loaded
        guard currentConversationId != nil || initialConversationId != nil else {
            return
        }

        // Refresh to catch any messages that arrived while app was backgrounded
        Task {
            await refreshMessages()
        }
    }

    /// Refresh messages from the server (called when push notification arrives)
    private func refreshMessages() async {
        guard let conversationId = currentConversationId ?? initialConversationId else { return }

        do {
            let response = try await APIClient.shared.getMessages(conversationId: conversationId)
            // Only update if we have new messages
            if response.messages.count > messages.count {
                messages = response.messages
                claudeSessionId = response.conversation.claudeSessionId
                hasMoreMessages = response.hasMore ?? false
                nextMessageCursor = response.nextCursor
            }
        } catch {
            // Silently fail - this is a background refresh
        }
    }

    private func sendMessageStreaming(_ text: String, messageId: String) async {
        let token: String
        do {
            token = try await APIClient.shared.getValidToken()
        } catch {
            markMessageFailed(messageId)
            errorService.show("Not authenticated")
            return
        }

        isSending = true
        isStreaming = false  // Will become true when first chunk arrives
        streamingText = ""

        sseService.sendAndStream(
            message: text,
            conversationId: currentConversationId,
            token: token
        ) { [weak self] event in
            self?.handleSSEEvent(event, messageId: messageId, originalMessage: text)
        }
    }

    private func retryWithApprovedTools(
        message: String,
        conversationId: String,
        allowedTools: [String]
    ) async {
        let token: String
        do {
            token = try await APIClient.shared.getValidToken()
        } catch {
            errorService.show("Not authenticated")
            return
        }

        isSending = true
        isStreaming = false  // Will become true when first chunk arrives
        streamingText = ""

        sseService.retryWithApprovedTools(
            message: message,
            conversationId: conversationId,
            token: token,
            allowedTools: allowedTools
        ) { [weak self] event in
            self?.handleSSEEvent(event, messageId: nil, originalMessage: message)
        }
    }

    private func markMessageFailed(_ messageId: String) {
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index].sendFailed = true
        }
    }

    private func handleSSEEvent(_ event: SSEEvent, messageId: String?, originalMessage: String) {
        switch event.type {
        case .chunk:
            handleChunkEvent(event)
        case .segmentEnd:
            handleSegmentEndEvent(event)
        case .toolStart:
            handleToolStartEvent(event)
        case .toolEnd:
            handleToolEndEvent()
        case .complete:
            handleCompleteEvent(event)
        case .permissionRequired:
            handlePermissionRequiredEvent(event, originalMessage: originalMessage)
        case .noResponse:
            handleNoResponseEvent(event)
        case .error:
            handleErrorEvent(event, messageId: messageId)
        case .ping:
            break // Keep-alive, ignore
        }
    }

    // MARK: - SSE Event Handlers

    private func handleChunkEvent(_ event: SSEEvent) {
        guard let content = event.content else { return }
        if !isStreaming {
            isStreaming = true
        }
        streamingText += content
    }

    private func handleSegmentEndEvent(_ event: SSEEvent) {
        updateConversationId(from: event)

        let content = event.content ?? streamingText
        if !content.isEmpty {
            appendAssistantMessage(content: content)
        }
        streamingText = ""
        isStreaming = false
        // Note: isSending remains true - more content may come after tool execution
    }

    private func handleToolStartEvent(_ event: SSEEvent) {
        isToolExecuting = true
        currentToolName = event.toolName
        isStreaming = false
    }

    private func handleToolEndEvent() {
        isToolExecuting = false
        currentToolName = nil
    }

    private func handleCompleteEvent(_ event: SSEEvent) {
        updateConversationId(from: event)
        updateTitle(from: event)

        if !streamingText.isEmpty {
            appendAssistantMessage(content: streamingText)
        }
        resetStreamingState()
    }

    private func handlePermissionRequiredEvent(_ event: SSEEvent, originalMessage: String) {
        updateConversationId(from: event)

        if !streamingText.isEmpty {
            appendAssistantMessage(content: streamingText)
            streamingText = ""
        }

        isStreaming = false
        isToolExecuting = false
        currentToolName = nil

        if let denials = event.denials, !denials.isEmpty {
            pendingPermissionRequest = PendingPermissionRequest(
                conversationId: currentConversationId ?? "",
                originalMessage: originalMessage,
                denials: denials
            )
        }

        isSending = false
    }

    private func handleNoResponseEvent(_ event: SSEEvent) {
        updateConversationId(from: event)

        let systemMessage = Message(
            id: UUID().uuidString,
            conversationId: currentConversationId ?? "",
            role: .system,
            content: event.message ?? "Command completed with no visible output.",
            createdAt: DateParser.format(Date())
        )
        messages.append(systemMessage)

        resetStreamingState()
    }

    private func handleErrorEvent(_ event: SSEEvent, messageId: String?) {
        if let message = event.message {
            errorService.show(message)
        }
        if let messageId {
            markMessageFailed(messageId)
        }
        resetStreamingState()
    }

    // MARK: - Event Handler Helpers

    private func updateConversationId(from event: SSEEvent) {
        if let conversationId = event.conversationId {
            currentConversationId = conversationId
        }
    }

    private func updateTitle(from event: SSEEvent) {
        guard let title = event.title else { return }
        conversationTitle = title
        NotificationCenter.default.post(
            name: .conversationTitleUpdated,
            object: nil,
            userInfo: ["conversationId": currentConversationId ?? "", "title": title]
        )
    }

    private func appendAssistantMessage(content: String) {
        let message = Message(
            id: UUID().uuidString,
            conversationId: currentConversationId ?? "",
            role: .assistant,
            content: content,
            createdAt: DateParser.format(Date())
        )
        messages.append(message)
    }

    private func resetStreamingState() {
        streamingText = ""
        isStreaming = false
        isToolExecuting = false
        currentToolName = nil
        isSending = false
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let conversationTitleUpdated = Notification.Name("conversationTitleUpdated")
}
