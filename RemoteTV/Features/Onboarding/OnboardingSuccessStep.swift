import SwiftUI

struct OnboardingSuccessStep: View {
    let vm: OnboardingViewModel
    @State private var celebrate = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            CheckmarkBurst()
                .frame(height: 140)
                .padding(.bottom, 20)
            Text("You're all set!")
                .font(.title.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("RemoteTV is paired with \(vm.selectedDevice?.name ?? "your TV"). Just a couple of optional tips to make it even better.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Spacer(minLength: 12)
            OnboardingPrimaryButton(title: "Continue") { Task { await vm.continueFromSuccess() } }
                .padding(.bottom, 24)
        }
        .sensoryFeedback(.success, trigger: celebrate)
        .onAppear { celebrate = true }
    }
}

/// An animated checkmark that draws itself inside an expanding ring. Falls back to a static
/// checkmark when Reduce Motion is on.
private struct CheckmarkBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draw: CGFloat = 0
    @State private var ring: CGFloat = 0.6
    @State private var ringOpacity: CGFloat = 0

    var body: some View {
        ZStack {
            Circle().fill(Color.green.opacity(0.12)).frame(width: 132, height: 132).scaleEffect(ring)
            Circle().stroke(Color.green, lineWidth: 3).frame(width: 132, height: 132)
                .scaleEffect(ring).opacity(ringOpacity)
            CheckmarkShape()
                .trim(from: 0, to: draw)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                .frame(width: 60, height: 46)
        }
        .onAppear {
            guard !reduceMotion else { draw = 1; ring = 1; ringOpacity = 1; return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { ring = 1; ringOpacity = 1 }
            withAnimation(.easeInOut(duration: 0.45).delay(0.18)) { draw = 1 }
        }
        .accessibilityHidden(true)
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
