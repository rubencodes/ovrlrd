import SwiftUI

struct ConversationRow: View {

    // MARK: - Public Properties

    let conversation: Conversation
    var isPinned: Bool = false

    // MARK: - Private Properties

    private var date: Date? {
        DateParser.parse(conversation.updatedAt)
    }

    // MARK: - Body

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title ?? "New Conversation")
                    .font(.headline)
                    .lineLimit(1)

                Group {
                    if let date {
                        RelativeTimeText(date: date)
                    } else {
                        Text(conversation.updatedAt)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Previews

#Preview {
    List {
        ConversationRow(conversation: .mockToday)
        ConversationRow(conversation: .mockYesterday)
        ConversationRow(conversation: .mockLastWeek)
        ConversationRow(conversation: .mockOlder)
    }
}
