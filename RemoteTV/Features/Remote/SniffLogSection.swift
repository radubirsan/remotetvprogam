import RemoteTVCore
import SwiftUI

/// Read-only scroll of recent Samsung control-channel traffic. Purely a debugging aid —
/// lives under the bottom action row so the user can watch the WebSocket while triggering
/// things on the TV (e.g. launching an app from the physical remote to capture its ID).
struct SniffLogSection: View {
    let entries: [SniffLogEntry]
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("WebSocket Sniffer")
                    .font(.headline)
                Spacer()
                Button("Clear", action: onClear)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(entries.isEmpty)
            }

            ScrollView {
                LazyVStack(alignment: .leading) {
                    if entries.isEmpty {
                        Text("No messages yet. Launch an app on the TV with the physical remote and watch here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(entries) { entry in
                            SniffLogRow(entry: entry)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)
            .frame(minHeight: 160, maxHeight: 260)
            .background(.quaternary)
            .clipShape(.rect(cornerRadius: 8))
        }
    }
}

private struct SniffLogRow: View {
    let entry: SniffLogEntry

    var body: some View {
        HStack(alignment: .top) {
            Text(prefix)
                .font(.caption.monospaced())
                .foregroundStyle(color)
            Text(entry.text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private var prefix: String {
        switch entry.direction {
        case .inbound: "<-"
        case .outbound: "->"
        case .info: " ."
        }
    }

    private var color: Color {
        switch entry.direction {
        case .inbound: .blue
        case .outbound: .orange
        case .info: .secondary
        }
    }
}
