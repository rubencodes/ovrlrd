import SwiftUI

struct PermissionApprovalSheet: View {

    // MARK: - Properties

    let request: ChatViewModel.PendingPermissionRequest
    let onApprove: () -> Void
    let onDeny: () -> Void

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: "lock.shield")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                    .padding(.top, 8)

                // Title
                Text("Permission Required")
                    .font(.title2)
                    .fontWeight(.semibold)

                // Description
                Text("Claude wants to perform the following action\(request.denials.count > 1 ? "s" : ""):")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // List of requested permissions
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(request.denials) { denial in
                        HStack(spacing: 12) {
                            Image(systemName: ToolMetadata.icon(for: denial.toolName))
                                .foregroundStyle(.blue)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(denial.toolName)
                                    .font(.headline)
                                Text(denial.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal)

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    Button(action: onApprove) {
                        Text("Allow")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel("Allow")
                    .accessibilityHint("Grants Claude permission to perform the requested actions")

                    Button(action: onDeny) {
                        Text("Deny")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel("Deny")
                    .accessibilityHint("Denies Claude permission to perform the requested actions")
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDeny)
                }
            }
        }
    }

}

// MARK: - Previews

#Preview("Single Permission") {
    PermissionApprovalSheet(
        request: ChatViewModel.PendingPermissionRequest(
            conversationId: "test",
            originalMessage: "Create a file",
            denials: [
                PermissionDenial(
                    toolName: "Write",
                    toolUseId: "test-1",
                    toolInput: ["file_path": AnyCodable("/tmp/test.txt"), "content": AnyCodable("hello")]
                )
            ]
        ),
        onApprove: {},
        onDeny: {}
    )
}

#Preview("Multiple Permissions") {
    PermissionApprovalSheet(
        request: ChatViewModel.PendingPermissionRequest(
            conversationId: "test",
            originalMessage: "Run setup script",
            denials: [
                PermissionDenial(
                    toolName: "Bash",
                    toolUseId: "test-1",
                    toolInput: ["command": AnyCodable("npm install")]
                ),
                PermissionDenial(
                    toolName: "Write",
                    toolUseId: "test-2",
                    toolInput: ["file_path": AnyCodable("/project/config.json")]
                )
            ]
        ),
        onApprove: {},
        onDeny: {}
    )
}
