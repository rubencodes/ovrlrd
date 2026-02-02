import Combine
import Foundation
import SwiftUI

@MainActor
@Observable
final class ChatListViewModel {

    // MARK: - Public Properties

    private(set) var conversations: [Conversation] = []
    private(set) var isLoading = true
    private(set) var isLoadingMore = false
    private(set) var hasMore = false
    private(set) var pinnedIds: Set<String> = []

    /// Conversations sorted with pinned ones first
    var sortedConversations: [Conversation] {
        conversations.sorted { a, b in
            let aPinned = pinnedIds.contains(a.id)
            let bPinned = pinnedIds.contains(b.id)
            if aPinned != bPinned {
                return aPinned
            }
            // Both pinned or both unpinned - maintain original order (by updatedAt)
            return false
        }
    }

    // MARK: - Private Properties

    private let errorService: ErrorService
    private var nextCursor: String?
    private static let pinnedIdsKey = "pinnedConversationIds"
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(errorService: ErrorService = .shared) {
        self.errorService = errorService
        self.pinnedIds = Self.loadPinnedIds()
        setupNotificationObserver()
    }

    init(conversations: [Conversation], isLoading: Bool = false, pinnedIds: Set<String> = []) {
        self.conversations = conversations
        self.isLoading = isLoading
        self.pinnedIds = pinnedIds
        self.errorService = .shared
    }

    private func setupNotificationObserver() {
        NotificationCenter.default.publisher(for: .conversationTitleUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let conversationId = notification.userInfo?["conversationId"] as? String,
                      let title = notification.userInfo?["title"] as? String else {
                    return
                }
                self?.handleTitleUpdate(conversationId: conversationId, title: title)
            }
            .store(in: &cancellables)
    }

    private func handleTitleUpdate(conversationId: String, title: String) {
        withAnimation(.snappy) {
            if let index = conversations.firstIndex(where: { $0.id == conversationId }) {
                conversations[index].title = title
            }
        }
    }

    // MARK: - Public Methods

    func loadConversations(forceRefresh: Bool = false) async {
        guard forceRefresh || conversations.isEmpty else {
            isLoading = false
            return
        }

        do {
            let response = try await APIClient.shared.getConversations()
            conversations = response.conversations
            hasMore = response.hasMore ?? false
            nextCursor = response.nextCursor
        } catch {
            errorService.show("Failed to load conversations: \(error.localizedDescription)")
        }
        isLoading = false
    }

    func loadMoreConversations() async {
        guard hasMore, !isLoadingMore, let cursor = nextCursor else { return }

        isLoadingMore = true
        do {
            let response = try await APIClient.shared.getConversations(cursor: cursor)
            conversations.append(contentsOf: response.conversations)
            hasMore = response.hasMore ?? false
            nextCursor = response.nextCursor
        } catch {
            errorService.show("Failed to load more conversations: \(error.localizedDescription)")
        }
        isLoadingMore = false
    }

    func deleteConversation(_ conversation: Conversation) async {
        do {
            try await APIClient.shared.deleteConversation(conversation.id)
            conversations.removeAll { $0.id == conversation.id }
            // Also remove from pinned if it was pinned
            if pinnedIds.contains(conversation.id) {
                pinnedIds.remove(conversation.id)
                Self.savePinnedIds(pinnedIds)
            }
        } catch {
            errorService.show("Failed to delete conversation: \(error.localizedDescription)")
        }
    }

    func isPinned(_ conversation: Conversation) -> Bool {
        pinnedIds.contains(conversation.id)
    }

    func togglePin(_ conversation: Conversation) {
        if pinnedIds.contains(conversation.id) {
            pinnedIds.remove(conversation.id)
        } else {
            pinnedIds.insert(conversation.id)
        }
        Self.savePinnedIds(pinnedIds)
    }

    // MARK: - Private Methods

    private static func loadPinnedIds() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: pinnedIdsKey) ?? []
        return Set(array)
    }

    private static func savePinnedIds(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: pinnedIdsKey)
    }
}
