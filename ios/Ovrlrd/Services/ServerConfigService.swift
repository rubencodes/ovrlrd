import Foundation
import SwiftUI

@MainActor
@Observable
final class ServerConfigService {

    // MARK: - Shared Instance

    static let shared = ServerConfigService()

    // MARK: - Public Properties

    var isConfigured: Bool {
        configuration != nil
    }
    var serverURL: URL? {
        configuration?.serverURL
    }
    var apiKey: String? {
        configuration?.apiKey
    }
    private(set) var connectionStatus: ConnectionStatus = .unknown

    // MARK: - private Properties

    private var configuration: Configuration?

    // MARK: - Types

    enum ConnectionStatus: Equatable {
        case unknown
        case checking
        case connected
        case failed(String)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    struct Configuration {
        let serverURL: URL
        let apiKey: String?

        static private let serverURLKey: String = "serverURL"

        static var stored: Configuration? {
            get {
                guard let urlString = UserDefaults.standard.string(forKey: serverURLKey),
                      let serverURL = URL(string: urlString) else {
                    return nil
                }

                let apiKey = KeychainService.get(.apiKey)
                return .init(serverURL: serverURL, apiKey: apiKey)
            } set {
                guard let newValue else {
                    UserDefaults.standard.removeObject(forKey: serverURLKey)
                    KeychainService.delete(.apiKey)
                    return
                }

                UserDefaults.standard.set(newValue.serverURL.absoluteString, forKey: serverURLKey)
                if let apiKey = newValue.apiKey, !apiKey.isEmpty {
                    KeychainService.save(apiKey, for: .apiKey)
                } else {
                    KeychainService.delete(.apiKey)
                }
            }
        }
    }

    // MARK: - Initialization

    private init(configuration: Configuration? = .stored) {
        self.configuration = configuration
    }

    // MARK: - Public Methods

    func update(configuration: Configuration) async -> Bool {
        connectionStatus = .checking
        guard await performHealthCheck(on: configuration) else {
            return false
        }

        self.configuration = configuration
        Configuration.stored = configuration
        connectionStatus = .connected
        return true
    }

    func clearConfiguration() {
        Configuration.stored = nil
        configuration = nil
        connectionStatus = .unknown
    }

    func checkConnection() async {
        guard let configuration else {
            connectionStatus = .failed("No server configured")
            return
        }

        connectionStatus = .checking
        guard await performHealthCheck(on: configuration) else {
            return
        }

        connectionStatus = .connected
    }

    // MARK: - Private Methods

    private func performHealthCheck(on configuration: Configuration) async -> Bool {
        guard let healthURL = URL(string: "/health", relativeTo: configuration.serverURL) else {
            connectionStatus = .failed("Invalid URL")
            return false
        }

        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 10
        if let apiKey = configuration.apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }

            if http.statusCode == 200 { return true }
            if http.statusCode == 401 || http.statusCode == 403 {
                connectionStatus = .failed("Invalid API key")
            } else {
                connectionStatus = .failed("Server error (\(http.statusCode))")
            }
            return false
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet:
                connectionStatus = .failed("No internet")
            case .timedOut:
                connectionStatus = .failed("Connection timed out")
            case .cannotFindHost, .cannotConnectToHost:
                connectionStatus = .failed("Server not found")
            default:
                connectionStatus = .failed(error.localizedDescription)
            }
            return false
        } catch {
            connectionStatus = .failed(error.localizedDescription)
            return false
        }
    }
}

// MARK: - Environment Key

@MainActor
private struct ServerConfigServiceKey: @preconcurrency EnvironmentKey {
    static var defaultValue: ServerConfigService { ServerConfigService.shared }
}

extension EnvironmentValues {
    @MainActor
    var serverConfigService: ServerConfigService {
        get { self[ServerConfigServiceKey.self] }
        set { self[ServerConfigServiceKey.self] = newValue }
    }
}

extension ServerConfigService {
    static var mock: Self {
        .init(configuration: .init(serverURL: URL(string: "https://localhost:3000")!, apiKey: nil))
    }
}
