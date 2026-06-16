import RemoteTVCore
import SwiftUI

struct ChannelSection: View {
    let onCommand: (TVCommand) async -> Void

    var body: some View {
        HStack {
            RemoteButton(label: "Previous channel", systemImage: "chevron.down.circle") {
                await onCommand(.channelDown)
            }
            RemoteButton(label: "Next channel", systemImage: "chevron.up.circle") {
                await onCommand(.channelUp)
            }
        }
    }
}
