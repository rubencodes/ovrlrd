import Foundation

actor APIClient {

    // MARK: - Shared Instance

    static let shared = APIClient()

    // MARK: - Private Properties

    private let decoder = JSONDecoder()
    private var isRefreshing = false

    // MARK: - Initialization

    private init() {}

    // MARK: - Configuration

    private func getBaseURL() async throws -> URL {
        let url = await MainActor.run {
            ServerConfigService.shared.serverURL
        }
        guard let url else {
            throw APIError.notConfigured
        }
        return url
    }

    private func getApiKey() async -> String? {
        await MainActor.run {
            ServerConfigService.shared.apiKey
        }
    }

    // MARK: - Authentication

    func authenticate(identityToken: String, deviceToken: String?) async throws -> AuthResponse {
        var body: [String: Any] = ["identityToken": identityToken]
        if let deviceToken {
            body["deviceToken"] = deviceToken
        }

        let request = try await makeRequest(
            path: "/auth",
            method: "POST",
            body: body,
            authenticated: false
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        return try decoder.decode(AuthResponse.self, from: data)
    }

    // MARK: - Conversations

    func getConversations(limit: Int? = nil, cursor: String? = nil) async throws -> ConversationsResponse {
        try await ensureValidToken()

        var queryItems: [URLQueryItem] = []
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        let request = try await makeRequest(
            path: "/chat",
            method: "GET",
            queryItems: queryItems.isEmpty ? nil : queryItems
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        return try decoder.decode(ConversationsResponse.self, from: data)
    }

    func getMessages(conversationId: String, limit: Int? = nil, cursor: String? = nil) async throws -> MessagesResponse {
        try await ensureValidToken()

        var queryItems: [URLQueryItem] = []
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        let request = try await makeRequest(
            path: "/chat/\(conversationId)",
            method: "GET",
            queryItems: queryItems.isEmpty ? nil : queryItems
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        return try decoder.decode(MessagesResponse.self, from: data)
    }

    func deleteConversation(_ conversationId: String) async throws {
        try await ensureValidToken()

        let request = try await makeRequest(
            path: "/chat/\(conversationId)",
            method: "DELETE"
        )
        let (_, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
    }

    // MARK: - Chat

    /// Store a permission event (approval/denial) without triggering Claude
    func storePermissionEvent(conversationId: String, role: String, content: String) async throws {
        try await ensureValidToken()

        let body: [String: Any] = [
            "role": role,
            "content": content
        ]

        let request = try await makeRequest(
            path: "/chat/\(conversationId)/events",
            method: "POST",
            body: body
        )

        let (_, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
    }

    // MARK: - Token Refresh

    /// Get a valid session token, refreshing if necessary
    /// Use this before making SSE requests which accept token as a parameter
    func getValidToken() async throws -> String {
        try await ensureValidToken()
        guard let token = KeychainService.get(.sessionToken) else {
            throw APIError.unauthorized
        }
        return token
    }

    /// Check if token needs refresh and refresh if necessary
    private func ensureValidToken() async throws {
        guard !isRefreshing else { return }

        guard let expiryString = KeychainService.get(.tokenExpiry),
              let expiryDate = ISO8601DateFormatter().date(from: expiryString) else {
            return // No expiry stored, let request proceed
        }

        let timeUntilExpiry = expiryDate.timeIntervalSinceNow
        if timeUntilExpiry > AppConstants.tokenRefreshBufferSeconds {
            return // Token still valid
        }

        // Token expired or expiring soon - refresh it
        try await refreshToken()
    }

    /// Refresh the session token
    private func refreshToken() async throws {
        guard let currentToken = KeychainService.get(.sessionToken) else {
            throw APIError.unauthorized
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let currentBaseURL = try await getBaseURL()
        let currentApiKey = await getApiKey()

        var request = URLRequest(url: currentBaseURL.appendingPathComponent("/auth/refresh"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let currentApiKey {
            request.setValue(currentApiKey, forHTTPHeaderField: "X-API-Key")
        }
        request.setValue("Bearer \(currentToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let authResponse = try decoder.decode(AuthResponse.self, from: data)

        // Save new token and expiry
        await MainActor.run {
            AuthService.shared.saveToken(authResponse.sessionToken, expiresIn: authResponse.expiresIn)
        }
    }

    // MARK: - Private Methods

    private func makeRequest(
        path: String,
        method: String,
        body: [String: Any]? = nil,
        queryItems: [URLQueryItem]? = nil,
        authenticated: Bool = true
    ) async throws -> URLRequest {
        let currentBaseURL = try await getBaseURL()
        let currentApiKey = await getApiKey()

        guard let pathURL = URL(string: path, relativeTo: currentBaseURL) else {
            throw APIError.invalidURL
        }

        var url = pathURL
        if let queryItems, !queryItems.isEmpty {
            guard var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: true) else {
                throw APIError.invalidURL
            }
            components.queryItems = queryItems
            guard let urlWithQuery = components.url else {
                throw APIError.invalidURL
            }
            url = urlWithQuery
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let currentApiKey {
            request.setValue(currentApiKey, forHTTPHeaderField: "X-API-Key")
        }

        if authenticated, let token = KeychainService.get(.sessionToken) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return request
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.serverError(httpResponse.statusCode)
        }
    }
}

// MARK: - APIError

enum APIError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Server not configured"
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Authentication required"
        case .serverError(let code):
            return "Server error (\(code))"
        }
    }
}
