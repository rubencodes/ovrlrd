import SwiftUI

// MARK: - View Modifier

/// A view modifier that animates the view popping in when it appears
struct PopInModifier: ViewModifier {

    // MARK: - Public Properties

    let delay: TimeInterval

    // MARK: - Private State

    @State private var isVisible = false

    // MARK: - Body

    func body(content: Content) -> some View {
        content
            .scaleEffect(isVisible ? 1 : 0.5)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.spring(duration: 0.4, bounce: 0.3).delay(delay)) {
                    isVisible = true
                }
            }
    }
}

// MARK: - View Extension

extension View {
    /// Animates the view popping in when it appears
    /// - Parameter delay: Delay before the animation starts (default: 0.2)
    func popIn(delay: TimeInterval = 0.2) -> some View {
        modifier(PopInModifier(delay: delay))
    }
}
