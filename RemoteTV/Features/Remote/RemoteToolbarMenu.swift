import SwiftUI

struct RemoteToolbarMenu: View {
    let onDisconnect: () -> Void
    let onForget: () -> Void

    var body: some View {
        Menu {
            Button("Disconnect & switch mode", systemImage: "arrow.left.arrow.right", action: onDisconnect)
            Button("Forget this TV", systemImage: "trash", role: .destructive, action: onForget)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }
}
