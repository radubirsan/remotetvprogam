import RemoteTVCore
import SwiftUI

struct DPadSection: View {
    let onCommand: (TVCommand) async -> Void

    var body: some View {
        VStack {
            RemoteButton(label: "Up", systemImage: "chevron.up") {
                await onCommand(.up)
            }
            HStack {
                RemoteButton(label: "Left", systemImage: "chevron.left") {
                    await onCommand(.left)
                }
                RemoteButton(label: "OK", systemImage: "circle.fill") {
                    await onCommand(.enter)
                }
                RemoteButton(label: "Right", systemImage: "chevron.right") {
                    await onCommand(.right)
                }
            }
            RemoteButton(label: "Down", systemImage: "chevron.down") {
                await onCommand(.down)
            }
        }
    }
}
