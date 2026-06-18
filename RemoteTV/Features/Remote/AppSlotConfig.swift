import SwiftUI

/// A launchable target a remote app-slot can be mapped to — a streaming app (by its Tizen
/// `appID`) or the special **Live TV** action.
struct RemoteAppShortcut: Identifiable, Hashable {
    /// The Tizen app ID, or ``liveTVID`` for the Live TV action.
    let id: String
    let name: String

    static let liveTVID = "__liveTV__"
    var isLiveTV: Bool { id == Self.liveTVID }

    static let liveTV = RemoteAppShortcut(id: liveTVID, name: "Live TV")

    /// Curated set offered in the picker (common streaming apps + Live TV). IDs are the
    /// modern Tizen (2019+) launcher IDs, matching `TVApp` / `KnownTVApps`.
    static let catalog: [RemoteAppShortcut] = [
        liveTV,
        .init(id: "111299001912", name: "YouTube"),
        .init(id: "3201907018807", name: "Netflix"),
        .init(id: "3201910019365", name: "Prime Video"),
        .init(id: "3201901017640", name: "Disney+"),
        .init(id: "3202301029760", name: "Max"),
        .init(id: "3201807016597", name: "Apple TV"),
        .init(id: "3201606009684", name: "Spotify"),
        .init(id: "3201910019457", name: "Paramount+"),
        .init(id: "3201911019187", name: "Peacock"),
    ]

    /// Resolves a stored id back to its shortcut (nil when empty / unknown).
    static func named(_ id: String) -> RemoteAppShortcut? {
        id.isEmpty ? nil : catalog.first { $0.id == id }
    }
}

/// Which of the three bottom app-slots is being configured.
enum SlotPosition: String, Identifiable, CaseIterable {
    case left, center, right
    var id: String { rawValue }
}

/// A bottom app-slot whose launch target the user picks. A **tap** launches the mapped app
/// (or opens the picker when unmapped); a **long-press** always opens the picker to re-map.
struct ConfigurableAppSlot: View {
    let size: CGFloat
    /// The currently-mapped shortcut, or nil when the slot is unconfigured.
    let shortcut: RemoteAppShortcut?
    /// Placeholder number ("1"/"2") shown when unconfigured; nil for the centre slot.
    var placeholderNumber: Int?
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var pressing = false
    @State private var feedback = 0

    var body: some View {
        ZStack {
            Circle().fill(RemoteTheme.buttonFace)
                .overlay(Circle().stroke(Color.white.opacity(0.05), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
            content
        }
        .frame(width: size, height: size)
        .scaleEffect(pressing ? 0.94 : 1)
        .animation(.easeOut(duration: 0.12), value: pressing)
        .contentShape(.circle)
        // A quick tap launches / opens the picker; a long-press (≥0.5s) re-maps. These two
        // are mutually exclusive by duration, so the separate gestures don't double-fire.
        .onTapGesture {
            feedback &+= 1
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            feedback &+= 1
            onLongPress()
        } onPressingChanged: { pressing = $0 }
        .sensoryFeedback(.impact(weight: .light), trigger: feedback)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(shortcut == nil ? "Choose an app for this button." : "Launches. Long press to change the app.")
    }

    @ViewBuilder
    private var content: some View {
        if let shortcut {
            if shortcut.isLiveTV {
                stack(top: "LIVE", bottom: "TV")
            } else {
                Text(shortcut.name.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.3)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(RemoteTheme.labelText)
                    .padding(.horizontal, 8)
            }
        } else {
            stack(top: "APP", bottom: placeholderNumber.map(String.init) ?? "SET")
        }
    }

    private func stack(top: String, bottom: String) -> some View {
        VStack(spacing: 2) {
            Text(top)
                .font(.system(size: 13, weight: .bold))
                .tracking(0.4)
            Text(bottom)
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.7)
        }
        .foregroundStyle(RemoteTheme.labelText)
    }

    private var accessibilityLabel: String {
        if let shortcut { "Launch \(shortcut.name)" } else { "App button, not set" }
    }
}

/// Picker sheet for an app-slot's launch target.
struct AppSlotConfigSheet: View {
    @Binding var selectedID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(RemoteAppShortcut.catalog) { shortcut in
                        Button {
                            selectedID = shortcut.id
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: shortcut.isLiveTV ? "tv" : "play.rectangle.fill")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                                Text(shortcut.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedID == shortcut.id {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Tap a button on the remote to launch it; long-press to come back here and change it.")
                }

                if !selectedID.isEmpty {
                    Button("Clear", role: .destructive) {
                        selectedID = ""
                        dismiss()
                    }
                }
            }
            .navigationTitle("Button app")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .tint(RemoteTheme.accent)
    }
}
