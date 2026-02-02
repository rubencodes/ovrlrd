import SwiftUI

@main
struct OvrlrdApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.authService) private var authService
    @Environment(\.serverConfigService) private var configService

    @State private var appState: AppState = .loading

    // MARK: - Types

    /// Represents the current state of the app's launch flow
    enum AppState {
        case loading
        case checkingAuth
        case authenticated
        case unauthenticated
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch appState {
                case .loading, .checkingAuth:
                    ProgressView()
                case .authenticated:
                    ChatListView()
                case .unauthenticated:
                    AuthView()
                }
            }
            .sheet(isPresented: showOnboardingBinding) {
                ServerOnboardingView { @MainActor in
                    appState = .checkingAuth
                    await authService.checkExistingSession()
                    appState = authService.isAuthenticated ? .authenticated : .unauthenticated
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled()
            }
            .task {
                await initializeApp()
            }
            .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                // Respond to auth state changes (sign in/out)
                if appState != .loading && appState != .checkingAuth {
                    appState = isAuthenticated ? .authenticated : .unauthenticated
                }
            }
            .onChange(of: configService.isConfigured) { _, isConfigured in
                // If config is cleared, go back to unauthenticated to show onboarding sheet
                if !isConfigured && appState == .authenticated {
                    authService.signOut()
                    appState = .unauthenticated
                }
            }
            .withErrorBanner()
        }
    }

    // MARK: - Private Properties

    private var showOnboardingBinding: Binding<Bool> {
        Binding(
            get: { !configService.isConfigured && appState == .unauthenticated },
            set: { _ in }
        )
    }

    // MARK: - Private Methods

    private func initializeApp() async {
        if configService.isConfigured {
            appState = .checkingAuth
            await configService.checkConnection()
            await authService.checkExistingSession()
            appState = authService.isAuthenticated ? .authenticated : .unauthenticated
        } else {
            appState = .unauthenticated
        }
    }
}
