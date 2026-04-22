import SwiftUI

/// The "kill the commercial" button. Sized deliberately large so it can be slapped
/// without aiming. When armed, it shows a live countdown and serves as the cancel
/// affordance too — a second tap unmutes immediately.
struct CommercialMuteSection: View {
    let remaining: Duration?
    let onToggle: () async -> Void

    var body: some View {
        Button {
            Task { await onToggle() }
        } label: {
            HStack {
                Image(systemName: icon)
                    .font(.largeTitle)
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.title2)
                        .bold()
                    Text(subtitle)
                        .font(.footnote)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding(.horizontal)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.extraLarge)
        .tint(isArmed ? .red : .orange)
        .accessibilityLabel(accessibilityLabel)
    }

    private var isArmed: Bool { remaining != nil }

    private var icon: String {
        isArmed ? "speaker.slash.fill" : "speaker.slash"
    }

    private var title: LocalizedStringKey {
        isArmed ? "Tap to Unmute" : "Mute 2 Min"
    }

    private var subtitle: LocalizedStringKey {
        if let remaining {
            "Unmutes in \(remaining.formatted(.time(pattern: .minuteSecond)))"
        } else {
            "Kill the commercial break"
        }
    }

    private var accessibilityLabel: Text {
        if let remaining {
            Text("Unmute now. Otherwise auto-unmutes in \(remaining.formatted(.time(pattern: .minuteSecond))).")
        } else {
            Text("Mute the TV for two minutes.")
        }
    }
}
