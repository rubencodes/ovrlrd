import AuthenticationServices
import Foundation
import SwiftUI

@MainActor
@Observable
final class AuthService {

    // MARK: - Shared Instance

    static let shared = AuthService()

    // MARK: - Public Properties

    private(set) var isAuthenticated = false
    private(set) var isCheckingSession = true
    private(set) var userId: String?

    // MARK: - Private Properties

    private var pendingDeviceToken: String?

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    func checkExistingSession() async {
        defer { isCheckingSession = false }

        guard KeychainService.get(.sessionToken) != nil else {
            isAuthenticated = false
            return
        }

        do {
            // Just verify we can make an authenticated request
            _ = try await APIClient.shared.getConversations(limit: 1)
            isAuthenticated = true
        } catch {
            KeychainService.delete(.sessionToken)
            isAuthenticated = false
        }
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws {
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AuthError.invalidCredential
        }

        let deviceToken = KeychainService.get(.deviceToken) ?? pendingDeviceToken

        let response = try await APIClient.shared.authenticate(
            identityToken: identityToken,
            deviceToken: deviceToken
        )

        saveToken(response.sessionToken, expiresIn: response.expiresIn)
        userId = response.userId
        isAuthenticated = true
    }

    /// Save token and calculate expiry time
    func saveToken(_ token: String, expiresIn: Int) {
        KeychainService.save(token, for: .sessionToken)

        let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
        let expiryString = ISO8601DateFormatter().string(from: expiryDate)
        KeychainService.save(expiryString, for: .tokenExpiry)
    }

    func updateDeviceToken(_ token: String) async {
        KeychainService.save(token, for: .deviceToken)
        pendingDeviceToken = token
    }

    func signOut() {
        KeychainService.delete(.sessionToken)
        KeychainService.delete(.tokenExpiry)
        isAuthenticated = false
        userId = nil
    }
}

// MARK: - AuthError

enum AuthError: Error {
    case invalidCredential
    case serverError
}

// MARK: - Environment Key

@MainActor
private struct AuthServiceKey: @preconcurrency EnvironmentKey {
    static var defaultValue: AuthService { AuthService.shared }
}

extension EnvironmentValues {
    @MainActor
    var authService: AuthService {
        get { self[AuthServiceKey.self] }
        set { self[AuthServiceKey.self] = newValue }
    }
}
