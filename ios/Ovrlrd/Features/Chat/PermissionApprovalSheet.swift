import SwiftUI

struct PermissionApprovalSheet: View {

    // MARK: - Properties

    let request: ChatViewModel.PendingPermissionRequest
    let onApprove: () -> Void
    let onDeny: () -> Void

    // MARK: - Body

    var body: some View {
        List {
            Section {
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
                    .listRowBackground(Color(.secondarySystemBackground))
                    .listRowSpacing(.zero)
                }
            } header: {
                VStack(spacing: 20) {
                    // Icon
                    Image(systemName: "lock.shield")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)

                    // Title
                    VStack(spacing: 12) {
                        Text("Permission Required")
                            .font(.title2)
                            .fontWeight(.semibold)

                        // Description
                        Text("Claude wants to perform the following action\(request.denials.count > 1 ? "s" : ""):")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .listRowInsets(.init(top: 20, leading: 16, bottom: 16, trailing: 16))
                .listRowBackground(Color.clear)
            } footer: {
                VStack(spacing: 4) {
                    Button(role: .confirm, action: onApprove) {
                        Text("Allow")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(.capsule)
                    }
                    .accessibilityLabel("Allow")
                    .accessibilityHint("Grants Claude permission to perform the requested actions")

                    Button(role: .cancel, action: onDeny) {
                        Text("Deny")
                            .font(.headline)
                            .padding()
                    }
                    .accessibilityLabel("Deny")
                    .accessibilityHint("Denies Claude permission to perform the requested actions")
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity)
                .listRowInsets(.init(top: 16, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.inset)
        .scrollIndicators(.hidden)
    }

}

// MARK: - Previews

#Preview("Single Permission") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            PermissionApprovalSheet(
                request: ChatViewModel.PendingPermissionRequest(
                    conversationId: "test",
                    originalMessage: "Create a file",
                    denials: [
                        PermissionDenial(
                            toolName: "Write",
                            toolUseId: "test-1",
                            toolInput: [
                                "file_path": AnyCodable("/tmp/test.txt"),
                                "content": AnyCodable("hello")
                            ]
                        )
                    ]
                ),
                onApprove: {},
                onDeny: {}
            )
            .presentationDetents([.medium])
            .presentationSizing(.page.fitted(horizontal: false, vertical: true))
        }
}

#Preview("Multiple Permissions") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
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
                        ),
                        PermissionDenial(
                            toolName: "Write",
                            toolUseId: "test-3",
                            toolInput: ["file_path": AnyCodable("/project/config.json")]
                        ),
                    ]
                ),
                onApprove: {},
                onDeny: {}
        )
        .presentationDetents([.medium])
    }
}
