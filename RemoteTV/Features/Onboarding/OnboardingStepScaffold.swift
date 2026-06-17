import SwiftUI

/// Shared layout for every onboarding step: a big SF Symbol, title, subtitle, custom
/// middle content, and a bottom action area — keeps every step visually consistent.
struct OnboardingStepScaffold<Content: View, Actions: View>: View {
    let symbol: String
    var symbolColor: Color = .accentColor
    let title: String
    let subtitle: String
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            Image(systemName: symbol)
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(symbolColor)
                .symbolRenderingMode(.hierarchical)
                .padding(.bottom, 20)
            Text(title)
                .font(.title.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            content()
                .padding(.top, 24)
            Spacer(minLength: 12)
            actions()
                .padding(.bottom, 24)
        }
    }
}

/// Full-width primary CTA at the bottom of onboarding steps — the handoff's Ember
/// accent-gradient button (see ``OnboardingPrimaryButtonStyle``).
struct OnboardingPrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(OnboardingPrimaryButtonStyle())
        .disabled(!enabled)
    }
}
