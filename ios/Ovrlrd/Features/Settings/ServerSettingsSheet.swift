import SwiftUI

struct ServerSettingsSheet: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.serverConfigService) private var configService
    @Environment(\.errorService) private var errorService

    // MARK: - State

    @State private var serverURL = ""
    @State private var apiKey = ""
    @State private var isSaving = false
    @State private var hasLoadedInitialValues = false
    @State private var showingDeleteConfirmation = false

    // MARK: - Public Properties

    var onDeleted: (() -> Void)?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                serverSection
                connectionSection
                deleteSection
            }
            .navigationTitle("Server Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear {
                if !hasLoadedInitialValues {
                    serverURL = configService.serverURL?.absoluteString ?? ""
                    apiKey = configService.apiKey ?? ""
                    hasLoadedInitialValues = true
                }
            }
        }
    }

    // MARK: - Private Views

    private var serverSection: some View {
        Section {
            TextField("Server URL", text: $serverURL)
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            SecureField("API Key (optional)", text: $apiKey)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        } header: {
            Text("Server Configuration")
        }
    }

    private var connectionSection: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                connectionStatusView
            }
        } header: {
            Text("Connection")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Text("Delete Server Configuration")
                    Spacer()
                }
            }
            .confirmationDialog(
                "Delete Server Configuration?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteConfiguration()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove your server settings and sign you out. You'll need to reconfigure the server to continue using the app.")
            }
        }
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        switch configService.connectionStatus {
        case .unknown:
            Text("Unknown")
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking...")
                    .foregroundStyle(.secondary)
            }
        case .connected:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Connected")
                    .foregroundStyle(.green)
            }
        case .failed(let message):
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .foregroundStyle(.red)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                dismiss()
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                save()
            }
            .disabled(serverURL.isEmpty || isSaving)
        }
    }

    // MARK: - Private Methods

    private func save() {
        guard let url = URL.normalized(from: serverURL) else {
            errorService.show("Invalid URL format")
            return
        }

        isSaving = true

        Task {
            let success = await configService.update(configuration: .init(
                serverURL: url,
                apiKey: apiKey.isEmpty ? nil : apiKey
            ))

            isSaving = false

            if success {
                dismiss()
            } else {
                // Show the specific error from connectionStatus
                if case .failed(let message) = configService.connectionStatus {
                    errorService.show(message)
                } else {
                    errorService.show("Failed to connect to server")
                }
            }
        }
    }

    private func deleteConfiguration() {
        configService.clearConfiguration()
        dismiss()
        onDeleted?()
    }
}

// MARK: - Previews

#Preview {
    ServerSettingsSheet()
        .withErrorBanner()
}
