import SwiftUI

/// Plain (chrome-less) button style that adds a *double* haptic pulse plus a
/// "depressed key" visual: the rendered label multiplies down to fully black while
/// the user's finger is on the button, snapping back to its normal gradient on
/// release. Drop-in replacement for `.buttonStyle(.plain)` on the Samsung-style
/// remote controls — preserves the custom label rendering each call site already
/// provides while making every press feel mechanical.
///
/// Two distinct intensities give the press its character: the press-down impact is
/// soft enough to feel like the finger meeting a key, and the lift-up impact is firm
/// enough to feel like the key snapping back. Driven via SwiftUI's `sensoryFeedback`
/// modifier so it composes correctly with VoiceOver, Reduce Motion, and Settings →
/// Sounds & Haptics.
///
/// `colorMultiply` is used (rather than overlaying a black shape or recoloring the
/// label) so the style stays a single drop-in `ButtonStyle` — every existing button
/// keeps its own circle/capsule/rocker shape, gradient, and shadow; the multiply
/// just paints the rendered output black for the press window. `.white` is the
/// identity for `colorMultiply`, so the unpressed branch is a true no-op.
struct HapticPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .colorMultiply(configuration.isPressed ? .black : .white)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
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
