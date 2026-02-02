import SwiftUI

struct ChatListView: View {

    // MARK: - Environment

    @Environment(\.authService) private var authService

    // MARK: - State

    @State private var viewModel: ChatListViewModel
    @State private var navigationPath: [String] = []

    // MARK: - Initialization

    init(viewModel: ChatListViewModel = ChatListViewModel()) {
        self._viewModel = State(initialValue: viewModel)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navigationPath) {
            content
                .safeAreaBar(edge: .bottom) {
                    HStack {
                        Spacer(minLength: 0)
                        newChatButton
                    }
                    .padding(.horizontal)
                    .frame(minHeight: 62)
                }
                .navigationTitle("Chats")
                .navigationDestination(for: String.self) { conversationId in
                    ChatView(conversationId: conversationId.isEmpty ? nil : conversationId)
                }
                .toolbar { toolbarContent }
                .task { await viewModel.loadConversations() }
                .refreshable { await viewModel.loadConversations(forceRefresh: true) }
                .onChange(of: navigationPath) { oldPath, newPath in
                    // Reload conversations when navigating back to the list
                    if !oldPath.isEmpty && newPath.isEmpty {
                        Task {
                            await viewModel.loadConversations(forceRefresh: true)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .openConversation)) { notification in
                    if let conversationId = notification.userInfo?["conversationId"] as? String {
                        navigationPath.append(conversationId)
                    }
                }
        }
    }

    // MARK: - Private Views

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
        } else if viewModel.conversations.isEmpty {
            ContentUnavailableView(
                "No Conversations",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Start a new conversation with Claude")
            )
        } else {
            List {
                ForEach(viewModel.sortedConversations) { conversation in
                    NavigationLink(value: conversation.id) {
                        ConversationRow(
                            conversation: conversation,
                            isPinned: viewModel.isPinned(conversation)
                        )
                        .contentTransition(.numericText())
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            withAnimation(.snappy) {
                                viewModel.togglePin(conversation)
                            }
                        } label: {
                            if viewModel.isPinned(conversation) {
                                Label("Unpin", systemImage: "pin.slash")
                            } else {
                                Label("Pin", systemImage: "pin")
                            }
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteConversation(conversation)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .onAppear {
                        // Load more when approaching the end
                        if conversation.id == viewModel.sortedConversations.last?.id {
                            Task {
                                await viewModel.loadMoreConversations()
                            }
                        }
                    }
                }

                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .animation(.snappy, value: viewModel.sortedConversations.map(\.id))
            .animation(.snappy, value: viewModel.sortedConversations.map(\.title))
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            ServerStatusIndicator()
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(role: .destructive) {
                    authService.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
        }
    }

    private var newChatButton: some View {
        Button {
            navigationPath.append("")
        } label: {
            Image(systemName: "plus")
                .font(.title)
                .fontWeight(.semibold)
                .padding(8)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .buttonSizing(.fitted)
        .shadow(radius: 16)
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.7), trigger: navigationPath)
        .popIn()
    }
}

// MARK: - Previews

#Preview("With Conversations") {
    ChatListView(viewModel: ChatListViewModel(conversations: Conversation.mockList, isLoading: false))
}

#Preview("Empty") {
    ChatListView(viewModel: ChatListViewModel(conversations: [], isLoading: false))
}

#Preview("Loading") {
    ChatListView()
}
