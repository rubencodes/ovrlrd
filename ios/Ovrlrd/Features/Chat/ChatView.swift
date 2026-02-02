import MarkdownUI
import SwiftUI

struct ChatView: View {

    // MARK: - State

    @State private var viewModel: ChatViewModel
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    // MARK: - Initialization

    init(conversationId: String? = nil) {
        self._viewModel = State(initialValue: ChatViewModel(conversationId: conversationId))
    }

    init(viewModel: ChatViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    // MARK: - Body

    var body: some View {
        messageList
            .safeAreaBar(edge: .bottom) {
                MessageInputBar(
                    text: $inputText,
                    isLoading: viewModel.isSending,
                    isFocused: $isInputFocused,
                    onSend: sendMessage
                )
            }
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadMessages()
            }
            .onDisappear {
                viewModel.disconnectStream()
            }
            .sheet(item: $viewModel.pendingPermissionRequest) { request in
                PermissionApprovalSheet(
                    request: request,
                    onApprove: viewModel.approvePermission,
                    onDeny: viewModel.denyPermission
                )
                .presentationDetents([.medium])
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let sessionId = viewModel.claudeSessionId {
                            Button {
                                UIPasteboard.general.string = sessionId
                            } label: {
                                Label("Copy Session ID", systemImage: "doc.on.doc")
                            }
                        } else {
                            Text("No session ID yet")
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
    }

    // MARK: - Private Views

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    // Load more indicator at top
                    if viewModel.hasMoreMessages {
                        HStack {
                            Spacer()
                            if viewModel.isLoadingMore {
                                ProgressView()
                            } else {
                                Button("Load earlier messages") {
                                    Task {
                                        await viewModel.loadMoreMessages()
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.bottom, 8)
                    }

                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                        // Show timestamp if >1hr gap from previous message
                        if shouldShowTimestamp(at: index) {
                            if let date = DateParser.parse(message.createdAt) {
                                TimestampSeparator(date: date)
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }
                        }

                        MessageBubble(message: message)
                            .id(message.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity
                            ))
                    }

                    // Show streaming response
                    if viewModel.isStreaming && !viewModel.streamingText.isEmpty {
                        streamingBubble
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // Show appropriate indicator based on state
                    if viewModel.isSending && !viewModel.isStreaming {
                        if viewModel.isToolExecuting {
                            workingIndicator
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        } else {
                            loadingIndicator
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
                }
                .padding()
                .animation(.snappy, value: viewModel.messages.count)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isSending)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isToolExecuting)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.streamingText) {
                if viewModel.isStreaming {
                    scrollToBottom(proxy: proxy)
                }
            }
            .onChange(of: viewModel.isSending) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.isToolExecuting) {
                scrollToBottom(proxy: proxy)
            }
            .onTapGesture {
                isInputFocused = false
            }
        }
    }

    private var streamingBubble: some View {
        HStack {
            Markdown(viewModel.streamingText)
                .markdownTheme(.assistantBubble)
                .padding(12)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .contentShape(Rectangle())
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = viewModel.streamingText
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }

            Spacer(minLength: 60)
        }
        .id("streaming")
    }

    private var loadingIndicator: some View {
        HStack {
            ProgressView()
            Text("Claude is thinking...")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .id("loading")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Claude is thinking")
    }

    private var workingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude is working...")
                    .foregroundStyle(.secondary)
                if let toolName = viewModel.currentToolName {
                    Text(toolDisplayName(toolName))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding()
        .id("working")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Claude is working. \(viewModel.currentToolName.map { toolDisplayName($0) } ?? "")")
    }

    private func toolDisplayName(_ toolName: String) -> String {
        ToolMetadata.activityDescription(for: toolName)
    }

    // MARK: - Private Methods

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation {
            // Scroll to the appropriate anchor based on current state
            if viewModel.isToolExecuting {
                proxy.scrollTo("working", anchor: .bottom)
            } else if viewModel.isSending && !viewModel.isStreaming {
                proxy.scrollTo("loading", anchor: .bottom)
            } else if viewModel.isStreaming {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let lastMessage = viewModel.messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }

    private func sendMessage() {
        let text = inputText
        inputText = ""
        Task {
            await viewModel.sendMessage(text)
        }
    }

    private func shouldShowTimestamp(at index: Int) -> Bool {
        // First message always shows timestamp
        guard index > 0 else { return true }

        let currentMessage = viewModel.messages[index]
        let previousMessage = viewModel.messages[index - 1]

        guard let currentDate = DateParser.parse(currentMessage.createdAt),
              let previousDate = DateParser.parse(previousMessage.createdAt) else {
            return false
        }

        // Show timestamp if gap exceeds threshold
        return currentDate.timeIntervalSince(previousDate) > AppConstants.messageTimestampGapSeconds
    }
}

// MARK: - Previews

#Preview("Empty") {
    NavigationStack {
        ChatView(viewModel: ChatViewModel(messages: []))
    }
}

#Preview("With Messages") {
    NavigationStack {
        ChatView(viewModel: ChatViewModel(messages: Message.mockConversation))
    }
}

#Preview("Sending") {
    NavigationStack {
        ChatView(viewModel: ChatViewModel(messages: [.mockUserShort], isSending: true))
    }
}

#Preview("Long Conversation") {
    NavigationStack {
        ChatView(viewModel: ChatViewModel(messages: Message.mockConversation + [.mockUserCode, .mockAssistantCode]))
    }
}
