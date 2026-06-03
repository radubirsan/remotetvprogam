import SwiftUI

/// Side-panel rendering of the WebSocket sniff log. Used when the user opens the
/// "Sniff Log" panel from the gear menu — sits to the *right* of the remote and
/// fills its column at full height (vs the embedded ``SniffLogSection``'s 260pt cap).
/// Inline row rendering so this panel doesn't depend on the file-private row helper
/// inside ``SniffLogSection``.
@MainActor
struct RemoteSidePanelSniffLog: View {
    let entries: [SniffLogEntry]
    let onClear: @MainActor () -> Void
    /// Experimental "open Bixby?" candidates rendered as a button row above the log.
    let probes: [RemoteViewModel.BixbyProbe]
    /// Fires the tapped probe; the resulting frame/response shows up in `entries`.
    let onProbe: @MainActor (RemoteViewModel.BixbyProbe) -> Void
    /// Sends the test text phrase to the TV (logged in `entries`). Tap it after the
    /// BT_VOICE button to see whether Bixby reacts to injected text.
    let onSendText: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sniff Log")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Spacer()
                Button("Clear") {
                    onClear()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(entries.isEmpty)
            }

            // Bixby probe row — tap a candidate, watch the log below for the outbound
            // frame and any TV reply. Helps hunt for the code that opens the assistant.
            VStack(alignment: .leading, spacing: 4) {
                Text("Bixby probe")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(probes) { probe in
                        Button(probe.label) {
                            onProbe(probe)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.orange)
                    }
                    Button("Send text") {
                        onSendText()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.cyan)
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if entries.isEmpty {
                        Text("No messages yet. Launch an app on the TV with the physical remote and watch here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.top, 8)
                    } else {
                        ForEach(entries) { entry in
                            SniffLogPanelRow(entry: entry)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.35), in: .rect(cornerRadius: 8))
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RemoteTheme.body.opacity(0.5))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)
        }
        .colorScheme(.dark)
    }
}

private struct SniffLogPanelRow: View {
    let entry: SniffLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(prefix)
                .font(.caption.monospaced())
                .foregroundStyle(color)
            Text(entry.text)
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.85))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
    }

    private var prefix: String {
        switch entry.direction {
        case .inbound:  "<-"
        case .outbound: "->"
        case .info:     " ."
        }
    }

    private var color: Color {
        switch entry.direction {
        case .inbound:  .cyan
        case .outbound: .orange
        case .info:     .secondary
        }
    }
}
