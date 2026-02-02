import SwiftUI

struct MessageInputBar: View {

    // MARK: - Public Properties

    @Binding var text: String
    let isLoading: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    // MARK: - Private Properties

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            textField
                .padding(.vertical, 12)
            sendButton
        }
        .padding(.horizontal, 16)
        .glassEffect(.regular.interactive())
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.easeInOut(duration: 0.15), value: canSend)
    }

    // MARK: - Private Views

    private var textField: some View {
        TextField("Message", text: $text, axis: .vertical)
            .lineLimit(1...AppConstants.messageInputMaxLines)
            .focused(isFocused)
            .disabled(isLoading)
            .onSubmit {
                if canSend {
                    onSend()
                }
            }
            .submitLabel(.send)
            .accessibilityLabel("Message input")
            .accessibilityHint("Type your message to Claude")
    }

    @ViewBuilder
    private var sendButton: some View {
        if canSend {
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
            }
            .padding(.bottom, 6)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("Send message")
            .accessibilityHint("Sends your message to Claude")
        }
    }
}

// MARK: - Previews

#Preview("Empty") {
    @Previewable @State var text = ""
    @Previewable @FocusState var focused: Bool

    ZStack(alignment: .bottom) {
        ScrollView {
            LazyVStack {
                ForEach(0..<20) { i in
                    Text("Message \(i)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        }

        MessageInputBar(text: $text, isLoading: false, isFocused: $focused, onSend: {})
    }
}

#Preview("With Text") {
    @Previewable @State var text = "Hello, Claude!"
    @Previewable @FocusState var focused: Bool

    ZStack(alignment: .bottom) {
        Color.gray.opacity(0.2)
        MessageInputBar(text: $text, isLoading: false, isFocused: $focused, onSend: {})
    }
}

#Preview("Long Text") {
    @Previewable @State var text = "This is a longer message that might wrap to multiple lines to test how the input bar handles it."
    @Previewable @FocusState var focused: Bool

    ZStack(alignment: .bottom) {
        Color.gray.opacity(0.2)
        MessageInputBar(text: $text, isLoading: false, isFocused: $focused, onSend: {})
    }
}

#Preview("Loading") {
    @Previewable @State var text = ""
    @Previewable @FocusState var focused: Bool

    ZStack(alignment: .bottom) {
        Color.gray.opacity(0.2)
        MessageInputBar(text: $text, isLoading: true, isFocused: $focused, onSend: {})
    }
}
