////
////  RemoteSamsungStyle.swift
////  Another Remote
////
////  Original design — Samsung-style layout match.
////  Drop into an Xcode iOS project (iOS 16+, SwiftUI).
////  Designed for iPhone 16 Pro (393×852 pt). Scales to other sizes via the outer GeometryReader if needed.
////
//
//import SwiftUI
//
//// MARK: - Theme
//
//enum RemoteTheme {
//    static let bg = LinearGradient(
//        colors: [Color(red: 0.10, green: 0.10, blue: 0.11),
//                 Color(red: 0.04, green: 0.04, blue: 0.04)],
//        startPoint: .top, endPoint: .bottom
//    )
//
//    static let body = LinearGradient(
//        colors: [Color(red: 0.12, green: 0.12, blue: 0.13),
//                 Color(red: 0.055, green: 0.055, blue: 0.063)],
//        startPoint: .top, endPoint: .bottom
//    )
//
//    static let buttonFace = RadialGradient(
//        colors: [Color(red: 0.137, green: 0.137, blue: 0.153),
//                 Color(red: 0.086, green: 0.086, blue: 0.094),
//                 Color(red: 0.047, green: 0.047, blue: 0.055)],
//        center: UnitPoint(x: 0.35, y: 0.30),
//        startRadius: 0, endRadius: 28
//    )
//
//    static let dpadOuter = RadialGradient(
//        colors: [Color(red: 0.122, green: 0.122, blue: 0.133),
//                 Color(red: 0.075, green: 0.075, blue: 0.086),
//                 Color(red: 0.039, green: 0.039, blue: 0.047)],
//        center: UnitPoint(x: 0.5, y: 0.25),
//        startRadius: 10, endRadius: 90
//    )
//
//    static let dpadInner = RadialGradient(
//        colors: [Color(red: 0.173, green: 0.173, blue: 0.188),
//                 Color(red: 0.102, green: 0.102, blue: 0.114),
//                 Color(red: 0.047, green: 0.047, blue: 0.055)],
//        center: UnitPoint(x: 0.35, y: 0.30),
//        startRadius: 0, endRadius: 40
//    )
//
//    static let powerRed   = Color(red: 0.902, green: 0.224, blue: 0.275)
//    static let labelDim   = Color(red: 0.353, green: 0.353, blue: 0.369)
//    static let labelText  = Color(red: 0.812, green: 0.812, blue: 0.831)
//    static let iconColor  = Color(red: 0.863, green: 0.863, blue: 0.871)
//}
//
//// MARK: - Atoms
//
///// Round tactile button with inner-shadow + outer-shadow shading.
//struct CircleButton<Content: View>: View {
//    let size: CGFloat
//    var iconColor: Color = RemoteTheme.iconColor
//    var action: () -> Void = {}
//    @ViewBuilder var content: () -> Content
//
//    var body: some View {
//        Button(action: action) {
//            ZStack {
//                Circle().fill(RemoteTheme.buttonFace)
//                content().foregroundStyle(iconColor)
//            }
//            .frame(width: size, height: size)
//            .overlay(
//                Circle().stroke(Color.white.opacity(0.05), lineWidth: 0.5)
//            )
//            .shadow(color: .black.opacity(0.5), radius: 2, y: 2)
//        }
//        .buttonStyle(.plain)
//    }
//}
//
///// Pill-shaped rocker with two halves (e.g. volume +/- or channel up/down).
//struct Rocker<Top: View, Bottom: View>: View {
//    let width: CGFloat
//    let height: CGFloat
//    @ViewBuilder var top: () -> Top
//    @ViewBuilder var bottom: () -> Bottom
//    var topAction: () -> Void = {}
//    var bottomAction: () -> Void = {}
//
//    var body: some View {
//        ZStack {
//            Capsule().fill(RemoteTheme.buttonFace)
//                .overlay(Capsule().stroke(Color.white.opacity(0.05), lineWidth: 0.5))
//                .shadow(color: .black.opacity(0.5), radius: 2, y: 2)
//
//            HStack(spacing: 0) {
//                Button(action: topAction) {
//                    top().foregroundStyle(RemoteTheme.iconColor)
//                        .frame(maxWidth: .infinity, maxHeight: .infinity)
//                }
//                .buttonStyle(.plain)
//                Button(action: bottomAction) {
//                    bottom().foregroundStyle(RemoteTheme.iconColor)
//                        .frame(maxWidth: .infinity, maxHeight: .infinity)
//                }
//                .buttonStyle(.plain)
//            }
//        }
//        .frame(width: width, height: height)
//    }
//}
//
///// D-pad: two concentric circles. The outer ring is a 4-way swipe surface, the inner is the OK button.
//struct DPad: View {
//    let outerSize: CGFloat
//    let innerSize: CGFloat
//    var onUp: () -> Void = {}
//    var onDown: () -> Void = {}
//    var onLeft: () -> Void = {}
//    var onRight: () -> Void = {}
//    var onOK: () -> Void = {}
//
//    var body: some View {
//        ZStack {
//            // Outer ring — tap on the rim quadrants
//            Circle().fill(RemoteTheme.dpadOuter)
//                .frame(width: outerSize, height: outerSize)
//                .shadow(color: .black.opacity(0.6), radius: 4, y: 3)
//                .gesture(
//                    DragGesture(minimumDistance: 10)
//                        .onEnded { value in
//                            let dx = value.translation.width
//                            let dy = value.translation.height
//                            if abs(dx) > abs(dy) {
//                                dx > 0 ? onRight() : onLeft()
//                            } else {
//                                dy > 0 ? onDown() : onUp()
//                            }
//                        }
//                )
//
//            // Inner OK
//            Button(action: onOK) {
//                Circle().fill(RemoteTheme.dpadInner)
//                    .frame(width: innerSize, height: innerSize)
//                    .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 0.5))
//                    .shadow(color: .black.opacity(0.7), radius: 3, y: 2)
//            }
//            .buttonStyle(.plain)
//        }
//        .frame(width: outerSize, height: outerSize)
//    }
//}
//
///// Streaming-app slot: round button with a 1-2 line label.
//struct AppSlot: View {
//    let size: CGFloat
//    let label: String
//    var sublabel: String? = nil
//    var action: () -> Void = {}
//
//    var body: some View {
//        Button(action: action) {
//            ZStack {
//                Circle().fill(RemoteTheme.buttonFace)
//                    .overlay(Circle().stroke(Color.white.opacity(0.05), lineWidth: 0.5))
//                    .shadow(color: .black.opacity(0.5), radius: 2, y: 2)
//                VStack(spacing: 1) {
//                    Text(label)
//                        .font(.system(size: 9.5, weight: .bold))
//                        .tracking(0.3)
//                        .foregroundStyle(RemoteTheme.labelText)
//                    if let sublabel {
//                        Text(sublabel)
//                            .font(.system(size: 8, weight: .semibold))
//                            .foregroundStyle(RemoteTheme.labelText.opacity(0.7))
//                    }
//                }
//            }
//            .frame(width: size, height: size)
//        }
//        .buttonStyle(.plain)
//    }
//}
//
//// MARK: - Main view
//
//struct RemoteSamsungStyleView: View {
//    // Layout constants — match the design exactly.
//    // Coordinate system: top-left origin, points (pt) — same as iPhone 16 Pro screen.
//    private let W: CGFloat   = 393
//    private let H: CGFloat   = 852
//    private let RW: CGFloat  = 220   // remote body width
//    private let RH: CGFloat  = 720   // remote body height
//    private let RY: CGFloat  = 80    // remote top offset
//
//    private var RX: CGFloat { (W - RW) / 2 }   // 86.5
//
//    var body: some View {
//        ZStack(alignment: .topLeading) {
//            // Background
//            RemoteTheme.bg.ignoresSafeArea()
//
//            // Settings gear (top-right, outside the remote body)
//            Button {
//                // settings action
//            } label: {
//                Image(systemName: "gearshape")
//                    .font(.system(size: 16, weight: .regular))
//                    .foregroundStyle(Color(white: 0.6))
//                    .frame(width: 36, height: 36)
//                    .background(Color.white.opacity(0.04), in: Circle())
//            }
//            .buttonStyle(.plain)
//            .position(x: W - 18 - 18, y: 64 + 18)
//
//            // REMOTE BODY
//            ZStack(alignment: .topLeading) {
//                // Body shell
//                RoundedRectangle(cornerRadius: 38, style: .continuous)
//                    .fill(RemoteTheme.body)
//                    .frame(width: RW, height: RH)
//                    .overlay(
//                        RoundedRectangle(cornerRadius: 38, style: .continuous)
//                            .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
//                    )
//                    .shadow(color: .black.opacity(0.6), radius: 18, y: 12)
//
//                // ROW 1: Power (left), MIC label (center), Mic (right)
//                CircleButton(size: 36, iconColor: RemoteTheme.powerRed) {
//                    Image(systemName: "power")
//                        .font(.system(size: 16, weight: .heavy))
//                }
//                .position(x: 22 + 18, y: 26 + 18)
//
//                VStack(spacing: 2) {
//                    Circle().fill(Color(white: 0.16)).frame(width: 3, height: 3)
//                    Text("MIC")
//                        .font(.system(size: 8, weight: .bold))
//                        .tracking(1)
//                        .foregroundStyle(RemoteTheme.labelDim)
//                }
//                .position(x: RW / 2, y: 36)
//
//                CircleButton(size: 36) {
//                    Image(systemName: "mic")
//                        .font(.system(size: 14, weight: .regular))
//                }
//                .position(x: RW - 22 - 18, y: 26 + 18)
//
//                // ROW 2: Settings/123 (under power)
//                CircleButton(size: 36) {
//                    VStack(spacing: 0) {
//                        Image(systemName: "gearshape")
//                            .font(.system(size: 9, weight: .regular))
//                        Text("123")
//                            .font(.system(size: 7, weight: .bold))
//                            .tracking(0.4)
//                    }
//                }
//                .position(x: 22 + 18, y: 70 + 18)
//
//                // D-PAD
//                DPad(outerSize: 150, innerSize: 62)
//                    .position(x: RW / 2, y: 130 + 75)
//
//                // ROW 4: Back / Home / Play-Pause
//                CircleButton(size: 34) {
//                    Image(systemName: "arrow.uturn.backward")
//                        .font(.system(size: 14, weight: .semibold))
//                }
//                .position(x: 28 + 17, y: 312 + 17)
//
//                CircleButton(size: 42) {
//                    Image(systemName: "house.fill")
//                        .font(.system(size: 16, weight: .regular))
//                }
//                .position(x: RW / 2, y: 308 + 21)
//
//                CircleButton(size: 34) {
//                    Image(systemName: "playpause.fill")
//                        .font(.system(size: 13, weight: .regular))
//                }
//                .position(x: RW - 28 - 17, y: 312 + 17)
//
//                // ROW 5: Volume rocker (left)
//                Rocker(width: 72, height: 32) {
//                    Image(systemName: "minus").font(.system(size: 13, weight: .semibold))
//                } bottom: {
//                    Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
//                }
//                .position(x: 22 + 36, y: 372 + 16)
//
//                // ROW 5: Channel rocker (right)
//                Rocker(width: 72, height: 32) {
//                    Image(systemName: "chevron.up").font(.system(size: 12, weight: .semibold))
//                } bottom: {
//                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
//                }
//                .position(x: RW - 22 - 36, y: 372 + 16)
//
//                // CC/AD + mute label under volume rocker
//                HStack(spacing: 6) {
//                    Text("CC/AD")
//                    Image(systemName: "speaker.slash")
//                        .font(.system(size: 10, weight: .regular))
//                }
//                .font(.system(size: 8, weight: .bold))
//                .tracking(0.6)
//                .foregroundStyle(Color(white: 0.48))
//                .frame(width: 72)
//                .position(x: 22 + 36, y: 416)
//
//                // ROW 6: App slots
//                AppSlot(size: 42, label: "APP", sublabel: "1")
//                    .position(x: 22 + 21, y: 450 + 21)
//
//                AppSlot(size: 50, label: "LIVE", sublabel: "TV")
//                    .position(x: RW / 2, y: 446 + 25)
//
//                AppSlot(size: 42, label: "APP", sublabel: "2")
//                    .position(x: RW - 22 - 21, y: 450 + 21)
//
//                AppSlot(size: 50, label: "APP", sublabel: "3")
//                    .position(x: RW / 2, y: 510 + 25)
//
//                AppSlot(size: 42, label: "APP", sublabel: "4")
//                    .position(x: RW - 22 - 21, y: 514 + 21)
//
//                // Brand label
//                Text("ANOTHER REMOTE")
//                    .font(.system(size: 11, weight: .bold))
//                    .tracking(2)
//                    .foregroundStyle(RemoteTheme.labelDim)
//                    .frame(width: RW)
//                    .position(x: RW / 2, y: RH - 28 - 6)
//            }
//            .frame(width: RW, height: RH)
//            .offset(x: RX, y: RY)
//        }
//        .frame(width: W, height: H)
//    }
//}
//
//// MARK: - Preview
//
//#Preview {
//    RemoteSamsungStyleView()
//        .preferredColorScheme(.dark)
//}
