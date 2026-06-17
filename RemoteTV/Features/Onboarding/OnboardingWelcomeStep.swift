import SwiftUI

/// First-run welcome screen, redesigned to match `design_handoff_another_remote 2`.
///
/// A fixed headline + primary CTA sit below an auto-looping showcase of the app's three
/// headline features (Full Remote, TV Guide, Mute Timer). The previews crossfade every
/// 2.6 s; the caption, ambient glow, and page dots stay in sync with the visible preview.
/// Reduce Motion drops the scale animation (plain crossfade only).
///
/// Navigation is unchanged: "Get Started" runs the same `continueFromWelcome()` that drove
/// the old button; the new "Connect your TV" link skips the guide via `onConnect` (the
/// same exit `RootView` gets from Skip).
struct OnboardingWelcomeStep: View {
    let vm: OnboardingViewModel
    /// Skip the guided setup and go straight to connecting a TV (RootView's no-op finish).
    var onConnect: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0

    private let features = WelcomeFeature.all
    private let advance = Timer.publish(every: 2.6, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            brandMark
                .padding(.top, 8)

            featureStage
                .frame(maxHeight: .infinity)

            caption
                .padding(.horizontal, 36)
                .frame(minHeight: 64)

            pageDots
                .padding(.top, 18)
                .padding(.bottom, 14)

            headlineAndCTA
        }
        .onReceive(advance) { _ in
            withAnimation(.easeInOut(duration: 0.55)) {
                index = (index + 1) % features.count
            }
        }
    }

    private var feature: WelcomeFeature { features[index] }

    // MARK: Brand mark

    private var brandMark: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(colors: [OnboardingStyle.accent, OnboardingStyle.accent.opacity(0.53)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: "tv")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: OnboardingStyle.accent.opacity(0.33), radius: 7)
            Text("REMOTETV")
                .font(.system(size: 13, weight: .bold))
                .tracking(1)
                .foregroundStyle(OnboardingStyle.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("RemoteTV")
    }

    // MARK: Feature stage

    private var featureStage: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [OnboardingStyle.accent.opacity(0.13), .clear],
                        center: .center, startRadius: 0, endRadius: 140
                    )
                )
                .frame(width: 280, height: 280)
                .blur(radius: 8)

            ForEach(Array(features.enumerated()), id: \.element.id) { offset, feature in
                feature.preview
                    .opacity(offset == index ? 1 : 0)
                    .scaleEffect(scale(for: offset))
                    .animation(.easeInOut(duration: 0.55), value: index)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("\(feature.label). \(feature.detail)")
    }

    private func scale(for offset: Int) -> CGFloat {
        guard !reduceMotion else { return 1 }
        return offset == index ? 1 : 0.94
    }

    // MARK: Caption

    private var caption: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(OnboardingStyle.accent)
                    .frame(width: 5, height: 5)
                Text(feature.label.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(OnboardingStyle.accent)
            }
            Text(feature.detail)
                .font(.system(size: 14.5))
                .foregroundStyle(OnboardingStyle.secondaryText)
                .lineSpacing(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .id(index)
        .transition(.opacity.combined(with: .offset(y: 6)))
    }

    // MARK: Page dots

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(features.indices, id: \.self) { i in
                Capsule()
                    .fill(i == index ? OnboardingStyle.accent : Color.white.opacity(0.18))
                    .frame(width: i == index ? 20 : 6, height: 6)
            }
        }
        .animation(.snappy, value: index)
        .accessibilityHidden(true)
    }

    // MARK: Headline + CTA

    private var headlineAndCTA: some View {
        VStack(spacing: 0) {
            Text("Turn your iPhone into a remote for your Samsung TV")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.6)
                .lineSpacing(2)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            OnboardingPrimaryButton(title: "Get Started") {
                Task { await vm.continueFromWelcome() }
            }
            .padding(.top, 22)

            Button {
                onConnect()
            } label: {
                HStack(spacing: 4) {
                    Text("Already set up?")
                        .foregroundStyle(OnboardingStyle.subtleText)
                    Text("Connect your TV")
                        .foregroundStyle(OnboardingStyle.linkText)
                }
                .font(.system(size: 13.5, weight: .semibold))
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }
        .padding(.horizontal, 28)
    }
}

// MARK: - Feature model

private struct WelcomeFeature: Identifiable {
    let id: String
    let label: String
    let detail: String
    let preview: AnyView

    static let all: [WelcomeFeature] = [
        WelcomeFeature(
            id: "remote", label: "Full Remote",
            detail: "Every button from your physical remote — power, D-pad, volume, and voice.",
            preview: AnyView(WelcomePreviewRemote())
        ),
        WelcomeFeature(
            id: "guide", label: "TV Guide",
            detail: "See what's on now and next across all your channels at a glance.",
            preview: AnyView(WelcomePreviewGuide())
        ),
        WelcomeFeature(
            id: "timer", label: "Mute Timer",
            detail: "Silence the ad break and auto-unmute right when your show returns.",
            preview: AnyView(WelcomePreviewMuteTimer())
        ),
    ]
}

// MARK: - Feature previews (illustrative, non-interactive)

/// Mini skeuomorphic remote.
private struct WelcomePreviewRemote: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                faceButton(size: 30) {
                    Image(systemName: "power").font(.system(size: 14, weight: .bold))
                        .foregroundStyle(OnboardingStyle.accent)
                }
                Spacer()
                faceButton(size: 30) {
                    Image(systemName: "mic").font(.system(size: 13))
                        .foregroundStyle(Color(white: 0.81))
                }
            }

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(colors: [Color(white: 0.12), Color(white: 0.06), Color(white: 0.04)],
                                       center: UnitPoint(x: 0.5, y: 0.25), startRadius: 2, endRadius: 60)
                    )
                    .frame(width: 96, height: 96)
                Text("OK")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color(white: 0.48))
                    .frame(width: 42, height: 42)
                    .background(
                        Circle().fill(
                            RadialGradient(colors: [Color(white: 0.17), Color(white: 0.09), Color(white: 0.05)],
                                           center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: 26)
                        )
                    )
            }

            HStack(spacing: 12) {
                rocker { Image(systemName: "plus") } bottom: { Image(systemName: "minus") }
                rocker { Image(systemName: "chevron.up") } bottom: { Image(systemName: "chevron.down") }
            }
        }
        .padding(18)
        .frame(width: 150, height: 250)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x1F1F22), Color(hex: 0x0E0E10)],
                                     startPoint: .top, endPoint: .bottom))
        )
        .shadow(color: .black.opacity(0.5), radius: 15, y: 12)
    }

    private func faceButton<Content: View>(size: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: size, height: size)
            .background(
                Circle().fill(
                    RadialGradient(colors: [Color(white: 0.165), Color(white: 0.086), Color(white: 0.047)],
                                   center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7)
                )
            )
    }

    private func rocker<Top: View, Bottom: View>(
        @ViewBuilder top: () -> Top, @ViewBuilder bottom: () -> Bottom
    ) -> some View {
        VStack(spacing: 8) {
            top().font(.system(size: 12, weight: .semibold))
            bottom().font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Color(white: 0.81))
        .frame(width: 34, height: 56)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(
                RadialGradient(colors: [Color(white: 0.165), Color(white: 0.086), Color(white: 0.047)],
                               center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 40)
            )
        )
    }
}

/// Mini TV-guide card with four channel rows.
private struct WelcomePreviewGuide: View {
    private struct Row { let n: Int; let tint: Color; let title: String; let cat: String; let prog: Double }
    private var rows: [Row] {
        [
            Row(n: 2, tint: OnboardingStyle.channelTints[0], title: "Morning Briefing", cat: "NEWS", prog: 0.68),
            Row(n: 4, tint: OnboardingStyle.channelTints[1], title: "Lions vs Hawks", cat: "LIVE", prog: 0.34),
            Row(n: 7, tint: OnboardingStyle.channelTints[2], title: "The Long Horizon", cat: "MOVIE", prog: 0.41),
            Row(n: 9, tint: OnboardingStyle.channelTints[3], title: "Deep Ocean", cat: "DOC", prog: 0.55),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TV Guide")
                .font(.system(size: 14, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(.white)
            VStack(spacing: 9) {
                ForEach(rows, id: \.n) { row in
                    HStack(spacing: 9) {
                        Text("\(row.n)")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(
                                    LinearGradient(colors: [row.tint, row.tint.opacity(0.6)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            let live = row.cat == "LIVE"
                            Text(row.cat)
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(live ? Color(hex: 0xFF6B6B) : OnboardingStyle.secondaryText)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(live ? Color(red: 230/255, green: 57/255, blue: 70/255).opacity(0.2)
                                                   : Color.white.opacity(0.07))
                                )
                            Text(row.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(OnboardingStyle.primaryText)
                                .lineLimit(1)
                            Capsule().fill(.white.opacity(0.08))
                                .frame(height: 2.5)
                                .overlay(alignment: .leading) {
                                    GeometryReader { geo in
                                        Capsule().fill(OnboardingStyle.accent)
                                            .frame(width: geo.size.width * row.prog)
                                    }
                                }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 230, height: 250, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x16161A), Color(hex: 0x0C0C0E)],
                                     startPoint: .top, endPoint: .bottom))
        )
        .shadow(color: .black.opacity(0.5), radius: 15, y: 12)
    }
}

/// Mini mute-timer card with a circular countdown ring.
private struct WelcomePreviewMuteTimer: View {
    private let progress = 0.62

    var body: some View {
        VStack(spacing: 18) {
            Text("MUTE TIMER")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(OnboardingStyle.tertiaryText)

            ZStack {
                Circle().stroke(.white.opacity(0.08), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(OnboardingStyle.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(OnboardingStyle.accent)
                    Text("2:48")
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                    Text("until unmute")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(OnboardingStyle.tertiaryText)
                }
            }
            .frame(width: 140, height: 140)

            HStack(spacing: 8) {
                ForEach(Array(["5m", "10m", "30m"].enumerated()), id: \.offset) { i, label in
                    let selected = i == 1
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selected ? OnboardingStyle.buttonInk : Color(hex: 0xB0B0B4))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(selected ? OnboardingStyle.accent : Color.white.opacity(0.06))
                        )
                }
            }
        }
        .padding(20)
        .frame(width: 210, height: 250)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x16161A), Color(hex: 0x0C0C0E)],
                                     startPoint: .top, endPoint: .bottom))
        )
        .shadow(color: .black.opacity(0.5), radius: 15, y: 12)
    }
}

// MARK: - Hex helper (file-scoped)

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
