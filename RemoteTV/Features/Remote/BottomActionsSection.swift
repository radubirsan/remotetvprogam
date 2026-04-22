import SwiftUI

struct BottomActionsSection: View {
    let onCommand: (TVCommand) async -> Void

    var body: some View {
        HStack {
            RemoteButton(label: "Back", systemImage: "arrow.uturn.backward") {
                await onCommand(.back)
            }
            RemoteButton(label: "Home", systemImage: "house") {
                await onCommand(.home)
            }
            RemoteButton(label: "Live TV", systemImage: "tv") {
                await onCommand(.liveTV)
            }
            RemoteButton(label: "Power off", systemImage: "power", tint: .red) {
                await onCommand(.powerOff)
            }
        }
    }
}
