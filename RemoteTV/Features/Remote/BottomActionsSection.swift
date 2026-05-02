import SwiftUI

struct BottomActionsSection: View {
    let onCommand: (TVCommand) async -> Void
    /// Separate from ``onCommand`` because "go to live TV" is a compound action (EXIT then
    /// KEY_TV) rather than a single key press — see ``RemoteViewModel/goLive``.
    let onLiveTV: () async -> Void

    var body: some View {
        HStack {
            RemoteButton(label: "Back", systemImage: "arrow.uturn.backward") {
                await onCommand(.back)
            }
            RemoteButton(label: "Home", systemImage: "house") {
                await onCommand(.home)
            }
            RemoteButton(label: "Live TV", systemImage: "tv") {
                await onLiveTV()
            }
            RemoteButton(label: "Power off", systemImage: "power", tint: .red) {
                await onCommand(.power)
            }
        }
    }
}
