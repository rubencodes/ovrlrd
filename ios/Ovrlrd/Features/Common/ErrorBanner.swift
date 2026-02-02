import SwiftUI

struct ErrorBanner: View {

    // MARK: - Public Properties

    let error: AppError
    let onDismiss: () -> Void

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
                .font(.body)

            Text(error.message)
                .font(.subheadline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.red.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .padding(.horizontal, 16)
    }
}

// MARK: - View Modifier

struct ErrorBannerModifier: ViewModifier {

    // MARK: - Environment

    @Environment(\.errorService) private var errorService

    // MARK: - Body

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content

            if let error = errorService.currentError {
                ErrorBanner(error: error) {
                    errorService.dismiss()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(100)
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - View Extension

extension View {
    func withErrorBanner() -> some View {
        modifier(ErrorBannerModifier())
    }
}

// MARK: - Previews

#Preview("Short Error") {
    ErrorBanner(
        error: AppError(message: "Failed to send message. Please try again."),
        onDismiss: {}
    )
    .padding(.top, 50)
}

#Preview("Long Error") {
    ErrorBanner(
        error: AppError(message: "Network connection lost. Please check your internet connection and try again."),
        onDismiss: {}
    )
    .padding(.top, 50)
}

#Preview("In Context") {
    @Previewable @State var showError = true

    NavigationStack {
        List {
            Text("Item 1")
            Text("Item 2")
            Text("Item 3")
        }
        .navigationTitle("Demo")
    }
    .overlay(alignment: .top) {
        if showError {
            ErrorBanner(
                error: AppError(message: "Something went wrong"),
                onDismiss: { showError = false }
            )
            .padding(.top, 8)
        }
    }
}
