import SwiftUI

struct StatusPill: View {
    let state: TVConnectionState
    let mode: TVConnectionMode

    var body: some View {
        HStack {
            Image(systemName: mode == .secure ? "lock.fill" : "lock.open.fill")
            Text(statusLabel)
                .bold()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(backgroundColor, in: .capsule)
        .foregroundStyle(.white)
    }

    private var statusLabel: LocalizedStringKey {
        switch state {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting…"
        case .awaitingPairing: "Accept on TV"
        case .connected: "Connected"
        case .failed: "Failed"
        }
    }

    private var backgroundColor: Color {
        switch state {
        case .disconnected: .gray
        case .connecting, .awaitingPairing: .orange
        case .connected: .green
        case .failed: .red
        }
    }
}
