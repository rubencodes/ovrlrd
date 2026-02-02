import Foundation

extension URL {
    /// Creates a URL from a string, automatically adding https:// if no scheme is provided
    /// - Parameter string: The URL string (e.g., "example.com" or "https://example.com")
    /// - Returns: A normalized URL, or nil if the string is invalid
    static func normalized(from string: String) -> URL? {
        var urlString = string.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !urlString.isEmpty else { return nil }

        // Add https:// if no scheme provided
        if !urlString.contains("://") {
            urlString = "https://\(urlString)"
        }

        return URL(string: urlString)
    }
}
