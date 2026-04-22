import SwiftUI

/// Large, tappable button used throughout the remote UI. Accepts an async action so callers
/// can await the underlying service without wrapping every call in a `Task`.
struct RemoteButton: View {
    let label: LocalizedStringKey
    let systemImage: String
    var tint: Color = .accentColor
    let action: () async -> Void

    var body: some View {
        Button(label, systemImage: systemImage) {
            Task { await action() }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.extraLarge)
        .labelStyle(.iconOnly)
        .tint(tint)
    }
}
