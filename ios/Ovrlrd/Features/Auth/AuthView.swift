import AuthenticationServices
import SwiftUI

struct AuthView: View {

    // MARK: - Environment

    @Environment(\.authService) private var authService
    @Environment(\.errorService) private var errorService
    @Environment(\.serverConfigService) private var configService

    // MARK: - State

    @State private var isLoading = false
    @State private var showingServerSettings = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 32) {
            headerContent
                .padding(.vertical, 100)
            Spacer()
            Group {
                signInContent
                serverInfoContent
            }
            .opacity(configService.isConfigured ? 1 : 0)
            Spacer()
                .frame(height: 48)
        }
        .padding(.horizontal, 32)
        .animation(.smooth, value: configService.isConfigured)
        .animation(.smooth, value: configService.connectionStatus)
        .sheet(isPresented: $showingServerSettings) {
            ServerSettingsSheet()
        }
    }

    // MARK: - Private Views

    private var headerContent: some View {
        VStack(spacing: 16) {
            Text("Ovrlrd")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Your remote command center")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var signInContent: some View {
        if isLoading {
            ProgressView()
        } else {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email]
            } onCompletion: { result in
                handleSignInResult(result)
            }
            .signInWithAppleButtonStyle(.black)
            .opacity(configService.connectionStatus != .connected ? 0.2 : 1)
            .disabled(configService.connectionStatus != .connected)
            .frame(height: 48)
        }
    }

    private var serverInfoContent: some View {
        Button {
            showingServerSettings = true
        } label: {
            HStack(spacing: 8) {
                connectionStatusDot
                if let host = configService.serverURL?.host() {
                    Text(host)
                        .font(.footnote)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }

    private var connectionStatusDot: some View {
        Circle()
            .fill(connectionStatusColor)
            .frame(width: 8, height: 8)
    }

    private var connectionStatusColor: Color {
        switch configService.connectionStatus {
        case .unknown:
            return .gray
        case .checking:
            return .orange
        case .connected:
            return .green
        case .failed:
            return .red
        }
    }

    // MARK: - Private Methods

    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorService.show("Invalid credential type")
                return
            }

            isLoading = true

            Task {
                do {
                    try await authService.signInWithApple(credential: credential)
                } catch {
                    errorService.show("Sign in failed. Please try again.")
                }
                isLoading = false
            }

        case .failure(let error):
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorService.show("Sign in failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Previews

#Preview {
    AuthView()
        .environment(\.serverConfigService, .mock)
        .withErrorBanner()
}
