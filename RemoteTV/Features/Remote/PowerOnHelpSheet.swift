import SwiftUI

/// Modal explainer surfaced when Wake-on-LAN can't actually wake the TV. Reused by
/// both the Discovery empty state and the Remote screen's power-button long-press
/// in wake mode — keeping it as one type avoids the help text drifting between the
/// two surfaces.
@MainActor
struct PowerOnHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("If Power On isn't working") {
                    Text("Samsung TVs only listen for Wake-on-LAN packets when Network Standby is enabled.")
                    Text("Turn the TV on and go to Settings → General → Network → Expert Settings → Power On with Mobile, then enable it.")
                    Text("You may also need to enable IP Remote in the same menu.")
                }
                Section("First-time setup") {
                    Text("Connect to the TV at least once while it's on. The app captures its MAC address on that first connect, which is what the magic packet needs.")
                }
            }
            .navigationTitle("Power On Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(RemoteTheme.accent)
    }
}
