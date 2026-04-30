import SwiftUI

/// Plain (chrome-less) button style that adds a *double* haptic pulse: a light tap on
/// press-down and a stronger snap on lift-up. Drop-in replacement for
/// `.buttonStyle(.plain)` on the Samsung-style remote controls — it preserves the
/// custom label rendering each call site already provides while making every press
/// feel mechanical.
///
/// Two distinct intensities give the press its character: the press-down impact is
/// soft enough to feel like the finger meeting a key, and the lift-up impact is firm
/// enough to feel like the key snapping back. Driven via SwiftUI's `sensoryFeedback`
/// modifier so it composes correctly with VoiceOver, Reduce Motion, and Settings →
/// Sounds & Haptics.
struct HapticPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .sensoryFeedback(trigger: configuration.isPressed) { _, isPressed in
                isPressed
                    ? .impact(weight: .light, intensity: 0.55)
                    : .impact(weight: .medium, intensity: 0.95)
            }
    }
}

extension ButtonStyle where Self == HapticPressStyle {
    /// Convenience accessor: `.buttonStyle(.hapticPress)`.
    static var hapticPress: HapticPressStyle { HapticPressStyle() }
}
