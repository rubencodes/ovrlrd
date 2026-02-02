import Foundation

/// Date parsing utilities for server timestamps and display formatting.
/// Isolated to main actor for thread-safe formatter access.
@MainActor
enum DateParser {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterNoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Server timestamp format: "yyyy-MM-dd HH:mm:ss.SSS"
    private static let serverFormatterWithMillis: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Server timestamp format: "yyyy-MM-dd HH:mm:ss"
    private static let serverFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func parse(_ string: String) -> Date? {
        if let date = isoFormatter.date(from: string) {
            return date
        }
        if let date = isoFormatterNoFractional.date(from: string) {
            return date
        }
        if let date = serverFormatterWithMillis.date(from: string) {
            return date
        }
        if let date = serverFormatter.date(from: string) {
            return date
        }
        return nil
    }

    static func format(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    /// Format a date for display in message timestamp (e.g., "Jan 30, 2026 at 2:30 PM")
    static func formatTimestamp(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }
}
