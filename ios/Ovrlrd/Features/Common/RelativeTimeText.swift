import SwiftUI

struct RelativeTimeText: View {

    // MARK: - Public Properties

    let date: Date

    // MARK: - Private Properties

    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    // MARK: - Body

    var body: some View {
        // TimelineView updates periodically - every minute is sufficient for "X ago" display
        TimelineView(.periodic(from: date, by: 60)) { _ in
            Text(Self.formatter.localizedString(for: date, relativeTo: Date()))
        }
    }
}

// MARK: - Previews

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        RelativeTimeText(date: Date())
        RelativeTimeText(date: Date().addingTimeInterval(-60))
        RelativeTimeText(date: Date().addingTimeInterval(-3600))
        RelativeTimeText(date: Date().addingTimeInterval(-86400))
        RelativeTimeText(date: Date().addingTimeInterval(-604800))
    }
    .padding()
}
