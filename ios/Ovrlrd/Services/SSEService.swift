import Foundation

// MARK: - Permission Denial

struct PermissionDenial: Codable, Identifiable {
    let toolName: String
    let toolUseId: String
    let toolInput: [String: AnyCodable]

    var id: String { toolUseId }

    enum CodingKeys: String, CodingKey {
        case toolName = "tool_name"
        case toolUseId = "tool_use_id"
        case toolInput = "tool_input"
    }

    /// Human-readable description of what the tool wants to do
    var description: String {
        switch toolName {
        case "Write":
            if let path = toolInput["file_path"]?.value as? String {
                return "Write to file: \(path)"
            }
            return "Write a file"
        case "Edit":
            if let path = toolInput["file_path"]?.value as? String {
                return "Edit file: \(path)"
            }
            return "Edit a file"
        case "Bash":
            if let command = toolInput["command"]?.value as? String {
                let maxLength = AppConstants.toolCommandPreviewMaxLength
                let truncated = command.count > maxLength ? String(command.prefix(maxLength)) + "..." : command
                return "Run command: \(truncated)"
            }
            return "Run a shell command"
        default:
            return "Use \(toolName)"
        }
    }
}

// MARK: - AnyCodable helper for dynamic JSON

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool: try container.encode(bool)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        default: try container.encodeNil()
        }
    }
}

// MARK: - SSE Event Types

struct SSEEvent: Codable {
    let type: SSEEventType
    let content: String?
    let conversationId: String?
    let message: String?
    let denials: [PermissionDenial]?
    let toolName: String?
    let title: String?

    enum SSEEventType: String, Codable {
        case chunk
        case segmentEnd = "segment_end"
        case toolStart = "tool_start"
        case toolEnd = "tool_end"
        case complete
        case noResponse = "no_response"
        case permissionRequired = "permission_required"
        case error
        case ping
    }
}

// MARK: - SSE Service

@MainActor
@Observable
final class SSEService: NSObject {

    // MARK: - Public Properties

    private(set) var isConnected = false

    // MARK: - Private Properties

    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var buffer = ""
    private var onEvent: ((SSEEvent) -> Void)?
    private var pendingErrorStatusCode: Int?
    private var receivedTerminalEvent = false

    // MARK: - Initialization

    override init() {
        super.init()
    }

    // MARK: - Public Methods

    /// Send a message and stream the response via SSE
    func sendAndStream(
        message: String,
        conversationId: String?,
        token: String,
        allowedTools: [String]? = nil,
        onEvent: @escaping (SSEEvent) -> Void
    ) {
        disconnect()

        self.onEvent = onEvent
        self.receivedTerminalEvent = false

        // Use /chat/:id/stream for existing conversations, /chat/stream for new ones
        let path = if let conversationId {
            "chat/\(conversationId)/stream"
        } else {
            "chat/stream"
        }

        let configService = ServerConfigService.shared
        guard let baseURL = configService.serverURL,
              let url = URL(string: path, relativeTo: baseURL) else {
            onEvent(SSEEvent(type: .error, content: nil, conversationId: nil, message: "Invalid URL", denials: nil, toolName: nil, title: nil))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let apiKey = configService.apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = AppConstants.sseTimeoutSeconds

        var body: [String: Any] = ["message": message]
        if let allowedTools, !allowedTools.isEmpty {
            body["allowedTools"] = allowedTools
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = AppConstants.sseTimeoutSeconds
        configuration.timeoutIntervalForResource = AppConstants.sseTimeoutSeconds

        session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        task = session?.dataTask(with: request)
        task?.resume()

        isConnected = true
    }

    /// Retry a message with approved tools
    func retryWithApprovedTools(
        message: String,
        conversationId: String,
        token: String,
        allowedTools: [String],
        onEvent: @escaping (SSEEvent) -> Void
    ) {
        sendAndStream(
            message: message,
            conversationId: conversationId,
            token: token,
            allowedTools: allowedTools,
            onEvent: onEvent
        )
    }

    func disconnect() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        buffer = ""
        onEvent = nil  // Break any potential retain cycles
        pendingErrorStatusCode = nil
        isConnected = false
        // Note: receivedTerminalEvent is NOT reset here - it's checked by didCompleteWithError
        // which may run after disconnect(). It's reset in sendAndStream() instead.
    }
}

// MARK: - URLSessionDataDelegate

extension SSEService: URLSessionDataDelegate {

    nonisolated func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        // Check HTTP status code
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            Task { @MainActor in
                self.pendingErrorStatusCode = httpResponse.statusCode
            }
        }
        completionHandler(.allow)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard let string = String(data: data, encoding: .utf8) else { return }

        Task { @MainActor in
            // If we received an error status code, try to parse the error response
            if let statusCode = self.pendingErrorStatusCode {
                self.pendingErrorStatusCode = nil
                if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    self.onEvent?(SSEEvent(
                        type: .error,
                        content: nil,
                        conversationId: nil,
                        message: "Server error (\(statusCode)): \(errorResponse.error)",
                        denials: nil,
                        toolName: nil,
                        title: nil
                    ))
                    self.disconnect()
                    return
                }
            }
            self.processData(string)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        Task { @MainActor in
            // Capture state before any changes
            let callback = self.onEvent
            let alreadyReceivedTerminal = self.receivedTerminalEvent

            self.isConnected = false

            // Handle user-initiated cancellation silently (from disconnect())
            if let urlError = error as? URLError, urlError.code == .cancelled {
                return
            }

            // If we already received a terminal event (complete, error, etc.),
            // the connection closing is expected - don't send another error
            if alreadyReceivedTerminal {
                return
            }

            // For any other error or unexpected completion, notify the ViewModel
            // This ensures isSending is reset even if connection drops unexpectedly
            let errorMessage: String
            if let error {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = "Connection closed unexpectedly"
            }

            callback?(SSEEvent(
                type: .error,
                content: nil,
                conversationId: nil,
                message: errorMessage,
                denials: nil,
                toolName: nil,
                title: nil
            ))
        }
    }
}

// MARK: - Error Response

private struct ErrorResponse: Codable {
    let error: String
}

// MARK: - Private Methods

extension SSEService {

    private func processData(_ string: String) {
        buffer += string

        // Parse SSE format: "data: {...}\n\n"
        while let range = buffer.range(of: "\n\n") {
            let eventString = String(buffer[..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])

            // Handle multiple lines in event (SSE can have multiple "data:" lines)
            let lines = eventString.split(separator: "\n", omittingEmptySubsequences: false)
            var dataContent = ""

            for line in lines {
                if line.hasPrefix("data:") {
                    let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    dataContent += data
                }
            }

            guard !dataContent.isEmpty,
                  let jsonData = dataContent.data(using: .utf8) else {
                continue
            }

            do {
                let event = try JSONDecoder().decode(SSEEvent.self, from: jsonData)
                onEvent?(event)

                // Auto-disconnect on terminal events
                if event.type == .complete || event.type == .error || event.type == .permissionRequired || event.type == .noResponse {
                    receivedTerminalEvent = true
                    disconnect()
                }
            } catch {
                // If JSON parsing fails, treat as raw chunk
                onEvent?(SSEEvent(
                    type: .chunk,
                    content: dataContent,
                    conversationId: nil,
                    message: nil,
                    denials: nil,
                    toolName: nil,
                    title: nil
                ))
            }
        }
    }
}
