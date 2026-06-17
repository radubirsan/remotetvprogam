import SwiftUI

/// Shared design tokens + button styles for the setup guide, lifted from
/// `design_handoff_another_remote 2` (the onboarding mock). Dark-mode only.
///
/// The primary CTA style (full-width 54 pt, radius 16, Ember accent gradient, dark ink,
/// soft accent glow) is the canonical "primary action" look the handoff asks us to use
/// across every onboarding step — `OnboardingPrimaryButton` and the explicit
/// `.buttonStyle(OnboardingPrimaryButtonStyle())` call sites both route through it.
enum OnboardingStyle {

    // MARK: Colors

    /// Ember — the handoff's default accent.
    static let accent = Color(hex: 0xFF6B5A)
    static let accentLo = Color(hex: 0xC8281A)
    /// Dark ink that rides on top of the accent fill (button label color).
    static let buttonInk = Color(hex: 0x1A1A1D)

    static let primaryText = Color(hex: 0xE8E8EA)
    static let secondaryText = Color(hex: 0x9A9A9E)
    static let tertiaryText = Color(hex: 0x6A6A6E)
    /// Muted body for the "Already set up?" line.
    static let subtleText = Color(hex: 0x7A7A7E)
    /// Brighter link emphasis ("Connect your TV").
    static let linkText = Color(hex: 0xCFCFD2)

    /// Accent fill for the primary CTA: `linear-gradient(180deg, accent, accent cc)`.
    static let accentGradient = LinearGradient(
        colors: [accent, accent.opacity(0.8)],
        startPoint: .top, endPoint: .bottom
    )

    /// Onboarding backdrop: `radial-gradient(ellipse at 50% 12%, #1c1c20, #0b0b0d 55%, #060607)`.
    static let background = RadialGradient(
        stops: [
            .init(color: Color(hex: 0x1C1C20), location: 0),
            .init(color: Color(hex: 0x0B0B0D), location: 0.55),
            .init(color: Color(hex: 0x060607), location: 1),
        ],
        center: UnitPoint(x: 0.5, y: 0.12),
        startRadius: 0, endRadius: 620
    )

    /// Channel-badge tints used by the TV Guide feature preview.
    static let channelTints: [Color] = [
        0xE63946, 0x2A9D8F, 0xE9C46A, 0x457B9D,
    ].map { Color(hex: $0) }
}

// MARK: - Button styles

/// Primary CTA — full-width accent-gradient pill with dark ink and a soft glow.
struct OnboardingPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(OnboardingStyle.buttonInk)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(OnboardingStyle.accentGradient)
            )
            .shadow(color: OnboardingStyle.accent.opacity(isEnabled ? 0.4 : 0), radius: 12, y: 6)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Secondary action — same footprint as the primary, but a quiet white-fill surface.
/// Used where a step pairs a reject/confirm choice (e.g. the test step's "No").
struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(OnboardingStyle.primaryText)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.07))
            )
            .opacity(configuration.isPressed ? 0.65 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Tertiary text link ("Connect your TV", "Pick a different TV", "Continue anyway").
/// `prominent` brightens it for the primary link on the welcome screen.
struct OnboardingLinkButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(prominent ? OnboardingStyle.linkText : OnboardingStyle.subtleText)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Hex helper

private extension Color {
    /// `0xRRGGBB` literal → `Color`.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
