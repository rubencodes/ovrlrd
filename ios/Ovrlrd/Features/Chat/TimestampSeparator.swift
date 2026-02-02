import SwiftUI

struct TimestampSeparator: View {

    let date: Date

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        HStack {
            Spacer()
            Text(formattedDate)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var formattedDate: String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday, \(Self.timeFormatter.string(from: date))"
        } else {
            return Self.dateFormatter.string(from: date)
        }
    }
}

// MARK: - Previews

#Preview("Today") {
    TimestampSeparator(date: Date())
}

#Preview("Yesterday") {
    TimestampSeparator(date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
}

#Preview("Older") {
    TimestampSeparator(date: Calendar.current.date(byAdding: .day, value: -5, to: Date())!)
}
