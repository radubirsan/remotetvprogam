//
//  RemoteSamsungStyle.swift
//  Another Remote
//
//  Original design — Samsung-style layout, scaled up for iOS HIG compliance.
//  All interactive elements ≥ 44×44 pt minimum tappable area.
//  Drop into an Xcode iOS project (iOS 16+, SwiftUI). iPhone 16 Pro target.
//

import SwiftUI

// MARK: - Theme

public enum RemoteTheme {
    static let bg = LinearGradient(
        colors: [Color(red: 0.10, green: 0.10, blue: 0.11),
                 Color(red: 0.04, green: 0.04, blue: 0.04)],
        startPoint: .top, endPoint: .bottom
    )
    static let body = LinearGradient(
        colors: [Color(red: 0.12, green: 0.12, blue: 0.13),
                 Color(red: 0.055, green: 0.055, blue: 0.063)],
        startPoint: .top, endPoint: .bottom
    )
    static let buttonFace = RadialGradient(
        colors: [Color(red: 0.137, green: 0.137, blue: 0.153),
                 Color(red: 0.086, green: 0.086, blue: 0.094),
                 Color(red: 0.047, green: 0.047, blue: 0.055)],
        center: UnitPoint(x: 0.35, y: 0.30),
        startRadius: 0, endRadius: 40
    )
    static let dpadOuter = RadialGradient(
        colors: [Color(red: 0.122, green: 0.122, blue: 0.133),
                 Color(red: 0.075, green: 0.075, blue: 0.086),
                 Color(red: 0.039, green: 0.039, blue: 0.047)],
        center: UnitPoint(x: 0.5, y: 0.25),
        startRadius: 10, endRadius: 140
    )
    static let dpadInner = RadialGradient(
        colors: [Color(red: 0.173, green: 0.173, blue: 0.188),
                 Color(red: 0.102, green: 0.102, blue: 0.114),
                 Color(red: 0.047, green: 0.047, blue: 0.055)],
        center: UnitPoint(x: 0.35, y: 0.30),
        startRadius: 0, endRadius: 60
    )
    static let powerRed   = Color(red: 0.902, green: 0.224, blue: 0.275)
    static let labelDim   = Color(red: 0.353, green: 0.353, blue: 0.369)
    static let labelText  = Color(red: 0.812, green: 0.812, blue: 0.831)
    static let iconColor  = Color(red: 0.863, green: 0.863, blue: 0.871)
}

// MARK: - Atoms

struct CircleButton<Content: View>: View {
    let size: CGFloat
    var iconColor: Color = RemoteTheme.iconColor
    var accessibilityLabel: String = ""
    var action: () -> Void = {}
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(RemoteTheme.buttonFace)
                content().foregroundStyle(iconColor)
            }
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color.white.opacity(0.05), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

struct Rocker<Top: View, Bottom: View>: View {
    let width: CGFloat
    let height: CGFloat
    var topLabel: String = ""
    var bottomLabel: String = ""
    @ViewBuilder var top: () -> Top
    @ViewBuilder var bottom: () -> Bottom
    var topAction: () -> Void = {}
    var bottomAction: () -> Void = {}

    var body: some View {
        ZStack {
            Capsule().fill(RemoteTheme.buttonFace)
                .overlay(Capsule().stroke(Color.white.opacity(0.05), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
            HStack(spacing: 0) {
                Button(action: topAction) {
                    top().foregroundStyle(RemoteTheme.iconColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(topLabel))

                Button(action: bottomAction) {
                    bottom().foregroundStyle(RemoteTheme.iconColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(bottomLabel))
            }
        }
        .frame(width: width, height: height)
    }
}

struct DPad: View {
    let outerSize: CGFloat
    let innerSize: CGFloat
    var onUp: () -> Void = {}
    var onDown: () -> Void = {}
    var onLeft: () -> Void = {}
    var onRight: () -> Void = {}
    var onOK: () -> Void = {}

    var body: some View {
        ZStack {
            Circle().fill(RemoteTheme.dpadOuter)
                .frame(width: outerSize, height: outerSize)
                .shadow(color: .black.opacity(0.6), radius: 6, y: 4)
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            if abs(dx) > abs(dy) {
                                dx > 0 ? onRight() : onLeft()
                            } else {
                                dy > 0 ? onDown() : onUp()
                            }
                        }
                )

            // Cardinal-direction tap zones — replaces the previous static hint dots
            // with real Buttons so each direction can be invoked by tap as well as
            // swipe. 48×48 hit areas (above HIG 44pt) with subtle chevron glyphs.
            DPadTapZone(systemImage: "chevron.up", accessibilityLabel: "Up", action: onUp)
                .offset(y: -outerSize / 2 + 28)
            DPadTapZone(systemImage: "chevron.down", accessibilityLabel: "Down", action: onDown)
                .offset(y: outerSize / 2 - 28)
            DPadTapZone(systemImage: "chevron.left", accessibilityLabel: "Left", action: onLeft)
                .offset(x: -outerSize / 2 + 28)
            DPadTapZone(systemImage: "chevron.right", accessibilityLabel: "Right", action: onRight)
                .offset(x: outerSize / 2 - 28)

            Button(action: onOK) {
                ZStack {
                    Circle().fill(RemoteTheme.dpadInner)
                        .frame(width: innerSize, height: innerSize)
                        .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.7), radius: 4, y: 2)
                    Text("OK")
                        .font(.system(size: 16, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Color.white.opacity(0.85))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("OK"))
        }
        .frame(width: outerSize, height: outerSize)
    }
}

/// Single cardinal direction button used inside ``DPad``. Sized comfortably above
/// HIG 44pt (60×60 hit area, +25% from the previous 48×48 to match the rest of the
/// scaled-up remote). Kept private to the design file — `DPad` is the public
/// composition.
private struct DPadTapZone: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(width: 60, height: 60)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

struct AppSlot: View {
    let size: CGFloat
    let label: String
    var sublabel: String? = nil
    var accessibilityName: String = ""
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(RemoteTheme.buttonFace)
                    .overlay(Circle().stroke(Color.white.opacity(0.05), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
                VStack(spacing: 2) {
                    Text(label)
                        .font(.system(size: 13, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(RemoteTheme.labelText)
                    if let sublabel {
                        Text(sublabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(RemoteTheme.labelText.opacity(0.7))
                    }
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityName.isEmpty ? "\(label) \(sublabel ?? "")" : accessibilityName))
    }
}

// MARK: - Main view

struct RemoteSamsungStyleView: View {
    // Layout — scaled up to meet HIG 44×44 pt minimums on every tappable element.
    // The remote body fills nearly the full iPhone width.
    private let W: CGFloat   = 393
    private let H: CGFloat   = 852
    private let RW: CGFloat  = 340   // remote body width (was 220 — much bigger)
    private let RH: CGFloat  = 760   // remote body height
    private let RY: CGFloat  = 60

    private var RX: CGFloat { (W - RW) / 2 }   // 26.5

    var body: some View {
        ZStack(alignment: .topLeading) {
            RemoteTheme.bg.ignoresSafeArea()

            // Settings gear — top-right of the screen, comfortably 44×44
            Button {
                // settings action
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color(white: 0.6))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.04), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .position(x: W - 32, y: 76)

            // REMOTE BODY
            ZStack(alignment: .topLeading) {
                // Body shell
                RoundedRectangle(cornerRadius: 56, style: .continuous)
                    .fill(RemoteTheme.body)
                    .frame(width: RW, height: RH)
                    .overlay(
                        RoundedRectangle(cornerRadius: 56, style: .continuous)
                            .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.6), radius: 22, y: 14)

                // ROW 1: Power (left), MIC label (center), Mic (right)
                CircleButton(size: 56, iconColor: RemoteTheme.powerRed,
                             accessibilityLabel: "Power") {
                    Image(systemName: "power")
                        .font(.system(size: 22, weight: .heavy))
                }
                .position(x: 40 + 28, y: 36 + 28)

                VStack(spacing: 3) {
                    Circle().fill(Color(white: 0.16)).frame(width: 4, height: 4)
                    Text("MIC")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(RemoteTheme.labelDim)
                }
                .position(x: RW / 2, y: 50)

                CircleButton(size: 56, accessibilityLabel: "Voice") {
                    Image(systemName: "mic")
                        .font(.system(size: 20, weight: .regular))
                }
                .position(x: RW - 40 - 28, y: 36 + 28)

                // ROW 2: Settings/123 (under power)
                CircleButton(size: 56, accessibilityLabel: "Number pad") {
                    VStack(spacing: 0) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 13, weight: .regular))
                        Text("123")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                    }
                }
                .position(x: 40 + 28, y: 110 + 28)

                // D-PAD — large; outer 220 / inner 92 both well above 44 pt
                DPad(outerSize: 220, innerSize: 96)
                    .position(x: RW / 2, y: 200 + 110)

                // ROW 4: Back / Home / Play-Pause
                CircleButton(size: 56, accessibilityLabel: "Back") {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 19, weight: .semibold))
                }
                .position(x: 40 + 28, y: 470 + 28)

                CircleButton(size: 64, accessibilityLabel: "Home") {
                    Image(systemName: "house.fill")
                        .font(.system(size: 22, weight: .regular))
                }
                .position(x: RW / 2, y: 466 + 32)

                CircleButton(size: 56, accessibilityLabel: "Play or pause") {
                    Image(systemName: "playpause.fill")
                        .font(.system(size: 18, weight: .regular))
                }
                .position(x: RW - 40 - 28, y: 470 + 28)

                // ROW 5: Volume rocker (left) — 120×52
                Rocker(width: 120, height: 52,
                       topLabel: "Volume down", bottomLabel: "Volume up") {
                    Image(systemName: "minus").font(.system(size: 18, weight: .semibold))
                } bottom: {
                    Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                }
                .position(x: 40 + 60, y: 562 + 26)

                // ROW 5: Channel rocker (right) — 120×52
                Rocker(width: 120, height: 52,
                       topLabel: "Channel up", bottomLabel: "Channel down") {
                    Image(systemName: "chevron.up").font(.system(size: 16, weight: .semibold))
                } bottom: {
                    Image(systemName: "chevron.down").font(.system(size: 16, weight: .semibold))
                }
                .position(x: RW - 40 - 60, y: 562 + 26)

                // CC/AD label under volume rocker (non-interactive)
                HStack(spacing: 8) {
                    Text("CC/AD")
                    Image(systemName: "speaker.slash")
                        .font(.system(size: 12, weight: .regular))
                }
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Color(white: 0.48))
                .frame(width: 120)
                .position(x: 40 + 60, y: 624)

                // ROW 6: App slots — all 56 pt
                AppSlot(size: 56, label: "APP", sublabel: "1", accessibilityName: "App 1")
                    .position(x: 40 + 28, y: 656 + 28)

                AppSlot(size: 64, label: "LIVE", sublabel: "TV", accessibilityName: "Live TV")
                    .position(x: RW / 2, y: 652 + 32)

                AppSlot(size: 56, label: "APP", sublabel: "2", accessibilityName: "App 2")
                    .position(x: RW - 40 - 28, y: 656 + 28)

                // Brand label
                Text("ANOTHER REMOTE")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(RemoteTheme.labelDim)
                    .frame(width: RW)
                    .position(x: RW / 2, y: RH - 28)
            }
            .frame(width: RW, height: RH)
            .offset(x: RX, y: RY)
        }
        .frame(width: W, height: H)
    }
}

// MARK: - Preview

#Preview {
    RemoteSamsungStyleView()
        .preferredColorScheme(.dark)
}
