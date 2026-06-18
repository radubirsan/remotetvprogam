//
//  RemoteSamsungStyle.swift
//
//  Design atoms for the Samsung-style remote: the shared dark theme and the reusable
//  button primitives (`CircleButton`, `Rocker`, `DPad`, `AppSlot`) composed by
//  `RemoteSamsungBody` and reused by Onboarding. All interactive elements keep a
//  ≥ 44×44 pt tappable area per the HIG.
//

import SwiftUI

// MARK: - Theme

enum RemoteTheme {
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
    /// Ember accent (#FF6B5A) — the app's primary tint, shared with the onboarding and
    /// TV Guide surfaces. Used to colour navigation-bar icons and back buttons.
    static let accent     = Color(red: 1.0, green: 0.420, blue: 0.353)
    /// Dark ink (#1A1A1D) that rides on top of the accent fill (accent-filled buttons).
    static let bgInk      = Color(red: 0.102, green: 0.102, blue: 0.114)
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
        .buttonStyle(.hapticPress)
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
                .buttonStyle(.hapticPress)
                .accessibilityLabel(Text(topLabel))

                Button(action: bottomAction) {
                    bottom().foregroundStyle(RemoteTheme.iconColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.hapticPress)
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
            .buttonStyle(.hapticPress)
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
        .buttonStyle(.hapticPress)
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
        .buttonStyle(.hapticPress)
        .accessibilityLabel(Text(accessibilityName.isEmpty ? "\(label) \(sublabel ?? "")" : accessibilityName))
    }
}

