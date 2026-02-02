import SwiftUI

@MainActor
@Observable
final class ErrorService {

    // MARK: - Shared Instance

    static let shared = ErrorService()

    // MARK: - Public Properties

    /// Current error (first in queue)
    var currentError: AppError? { errorQueue.first }

    // MARK: - Private Properties

    private var errorQueue: [AppError] = []
    private var dismissTask: Task<Void, Never>?

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    func show(_ error: AppError) {
        withAnimation(.spring(duration: 0.3)) {
            errorQueue.append(error)
        }
        // Start timer only if this is the first error
        if errorQueue.count == 1 {
            startDismissTimer(seconds: error.autoDismissAfter)
        }
    }

    func show(_ message: String, autoDismissAfter seconds: TimeInterval = 5) {
        show(AppError(message: message, autoDismissAfter: seconds))
    }

    func show(_ error: Error, autoDismissAfter seconds: TimeInterval = 5) {
        show(AppError(message: error.localizedDescription, autoDismissAfter: seconds))
    }

    func dismiss() {
        dismissTask?.cancel()
        guard !errorQueue.isEmpty else { return }

        withAnimation(.spring(duration: 0.3)) {
            _ = errorQueue.removeFirst()
        }

        // Start timer for next error using its specified duration
        if let nextError = errorQueue.first {
            startDismissTimer(seconds: nextError.autoDismissAfter)
        }
    }

    func dismissAll() {
        dismissTask?.cancel()
        withAnimation(.spring(duration: 0.3)) {
            errorQueue.removeAll()
        }
    }

    // MARK: - Private Methods

    private func startDismissTimer(seconds: TimeInterval) {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled {
                dismiss()
            }
        }
    }
}

// MARK: - AppError

struct AppError: Identifiable, Equatable, Sendable {

    // MARK: - Properties

    let id = UUID()
    let message: String
    let isRecoverable: Bool
    let autoDismissAfter: TimeInterval

    // MARK: - Initialization

    init(message: String, isRecoverable: Bool = true, autoDismissAfter: TimeInterval = 5) {
        self.message = message
        self.isRecoverable = isRecoverable
        self.autoDismissAfter = autoDismissAfter
    }
}

// MARK: - Environment Key

@MainActor
private struct ErrorServiceKey: @preconcurrency EnvironmentKey {
    static var defaultValue: ErrorService { ErrorService.shared }
}

extension EnvironmentValues {
    @MainActor
    var errorService: ErrorService {
        get { self[ErrorServiceKey.self] }
        set { self[ErrorServiceKey.self] = newValue }
    }
}
