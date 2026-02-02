import Foundation

struct Conversation: Identifiable, Codable {
    let id: String
    let userId: String
    let claudeSessionId: String?
    var title: String?
    let createdAt: String
    let updatedAt: String
}

// MARK: - Mock Data

extension Conversation {
    static let mockToday = Conversation(
        id: "conv-1",
        userId: "user-1",
        claudeSessionId: "abc123-session-id",
        title: "Help with SwiftUI layouts",
        createdAt: "2026-01-30 09:00:00",
        updatedAt: todayAt(hour: 14, minute: 30)
    )

    static let mockYesterday = Conversation(
        id: "conv-2",
        userId: "user-1",
        claudeSessionId: "def456-session-id",
        title: "Code review request",
        createdAt: "2026-01-29 10:00:00",
        updatedAt: yesterdayAt(hour: 18, minute: 45)
    )

    static let mockLastWeek = Conversation(
        id: "conv-3",
        userId: "user-1",
        claudeSessionId: nil,
        title: "Debugging async/await",
        createdAt: "2026-01-23 08:00:00",
        updatedAt: daysAgo(5, hour: 16, minute: 20)
    )

    static let mockOlder = Conversation(
        id: "conv-4",
        userId: "user-1",
        claudeSessionId: nil,
        title: nil,
        createdAt: "2025-12-15 11:00:00",
        updatedAt: "2025-12-15 15:30:00"
    )

    static let mockList: [Conversation] = [
        .mockToday,
        .mockYesterday,
        .mockLastWeek,
        .mockOlder
    ]

    // MARK: - Date Helpers

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = .current
        return f
    }()

    private static func todayAt(hour: Int, minute: Int) -> String {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        guard let date = calendar.date(from: components) else {
            return formatter.string(from: Date())
        }
        return formatter.string(from: date)
    }

    private static func yesterdayAt(hour: Int, minute: Int) -> String {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) else {
            return formatter.string(from: Date())
        }
        var components = calendar.dateComponents([.year, .month, .day], from: yesterday)
        components.hour = hour
        components.minute = minute
        guard let date = calendar.date(from: components) else {
            return formatter.string(from: Date())
        }
        return formatter.string(from: date)
    }

    private static func daysAgo(_ days: Int, hour: Int, minute: Int) -> String {
        let calendar = Calendar.current
        guard let baseDate = calendar.date(byAdding: .day, value: -days, to: Date()) else {
            return formatter.string(from: Date())
        }
        var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = hour
        components.minute = minute
        guard let date = calendar.date(from: components) else {
            return formatter.string(from: Date())
        }
        return formatter.string(from: date)
    }
}
