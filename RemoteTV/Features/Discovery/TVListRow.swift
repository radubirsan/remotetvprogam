import SwiftUI

/// A single row in ``DiscoveryView``'s list.
///
/// Available rows are fully tappable (the list's row selection handles that). Off rows add a
/// trailing Wake button when a MAC is on file; when it isn't, we show a footnote explaining
/// that the user needs to connect once while the TV is on to capture the MAC.
struct TVListRow: View {
    let row: DiscoveryViewModel.Row
    let isWaking: Bool
    let onWake: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(row.friendlyName)
                    .font(.headline)
                if !row.modelName.isEmpty {
                    Text("\(row.modelName) • \(row.ip)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text(row.ip)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if row.status == .off, row.mac == nil {
                    Text("Connect once while the TV is on to enable Wake.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            TVStatusBadge(status: row.status)

            if row.status == .off, row.mac != nil {
                Button("Wake", systemImage: "power", action: onWake)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .disabled(isWaking)
            }
        }
        .contentShape(.rect)
    }
}

/// A small pill that mirrors the row's live/off status. Kept as its own view so the
/// background shape and colors can be tuned without editing ``TVListRow``.
private struct TVStatusBadge: View {
    let status: DiscoveryViewModel.Row.Status

    var body: some View {
        Text(label)
            .font(.caption)
            .bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(.capsule)
    }

    private var label: LocalizedStringKey {
        switch status {
        case .available: "Available"
        case .off: "Off"
        }
    }

    private var foreground: Color {
        switch status {
        case .available: .green
        case .off: .secondary
        }
    }

    private var background: Color {
        switch status {
        case .available: .green.opacity(0.15)
        case .off: .secondary.opacity(0.15)
        }
    }
}
