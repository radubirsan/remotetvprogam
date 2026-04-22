import SwiftUI

struct VolumeSection: View {
    let onCommand: (TVCommand) async -> Void

    var body: some View {
        HStack {
            RemoteButton(label: "Volume down", systemImage: "speaker.wave.1") {
                await onCommand(.volumeDown)
            }
            RemoteButton(label: "Mute", systemImage: "speaker.slash") {
                await onCommand(.mute)
            }
            RemoteButton(label: "Volume up", systemImage: "speaker.wave.3") {
                await onCommand(.volumeUp)
            }
        }
    }
}
