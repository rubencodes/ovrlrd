import SwiftUI

struct ServerOnboardingView: View {

    // MARK: - Environment

    @Environment(\.serverConfigService) private var configService
    @Environment(\.errorService) private var errorService

    // MARK: - State

    @State private var serverURL = ""
    @State private var apiKey = ""
    @State private var isConnecting = false

    // MARK: - Public Properties

    var onComplete: () async -> Void

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: "server.rack")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                    .padding(.top, 8)

                // Title
                Text("Connect to Server")
                    .font(.title2)
                    .fontWeight(.semibold)

                // Description
                Text("Enter your server details to get started")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Form fields
                VStack(spacing: 12) {
                    TextField("Server URL", text: $serverURL)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    SecureField("API Key (optional)", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal)

                Spacer()

                // Connect button
                Button(action: connect) {
                    if isConnecting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Connect")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .background(serverURL.isEmpty ? Color.gray : Color.blue)
                .foregroundStyle(.white)
                .clipShape(.capsule)
                .disabled(serverURL.isEmpty || isConnecting)
                .animation(.smooth, value: serverURL.isEmpty || isConnecting)
            }
            .padding(.horizontal)
            .padding(.top, 32)
            .padding(.bottom, 8)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Private Methods

    private func connect() {
        guard let url = URL.normalized(from: serverURL) else {
            errorService.show("Invalid URL format")
            return
        }

        isConnecting = true

        Task {
            let success = await configService.update(configuration: .init(
                serverURL: url,
                apiKey: apiKey.isEmpty ? nil : apiKey
            ))

            isConnecting = false

            if success {
                await onComplete()
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
}

// MARK: - Previews

#Preview {
    Text("Auth View Background")
        .sheet(isPresented: .constant(true)) {
            ServerOnboardingView {
                print("Complete!")
            }
            .presentationDetents([.medium, .large])
        }
}
