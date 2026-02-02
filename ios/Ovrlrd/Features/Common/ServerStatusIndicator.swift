import SwiftUI

struct ServerStatusIndicator: View {

    // MARK: - Environment

    @Environment(\.authService) private var authService
    @Environment(\.serverConfigService) private var configService

    // MARK: - State

    @State private var showingSettings = false

    // MARK: - Body

    var body: some View {
        Button {
            showingSettings = true
        } label: {
            HStack(spacing: 6) {
                statusDot
                serverHostname
            }
            .padding(.leading, 8)
        }
        .buttonBorderShape(.capsule)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to open server settings")
        .sheet(isPresented: $showingSettings) {
            ServerSettingsSheet {
                authService.signOut()
            }
        }
    }

    // MARK: - Private Views

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    @ViewBuilder
    private var serverHostname: some View {
        if let host = configService.serverURL?.host() {
            Text(host)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch configService.connectionStatus {
        case .unknown:
            return .gray
        case .checking:
            return .orange
        case .connected:
            return .green
        case .failed:
            return .red
        }
    }

    private var accessibilityLabel: String {
        let host = configService.serverURL?.host() ?? "server"
        let status: String
        switch configService.connectionStatus {
        case .unknown:
            status = "unknown status"
        case .checking:
            status = "checking connection"
        case .connected:
            status = "connected"
        case .failed(let message):
            status = "disconnected, \(message)"
        }
        return "\(host), \(status)"
    }
}

// MARK: - Previews

#Preview("Connected") {
    NavigationStack {
        List {}
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ServerStatusIndicator()
                        .environment(\.serverConfigService, ServerConfigService.mock)
                }
            }
    }
}
