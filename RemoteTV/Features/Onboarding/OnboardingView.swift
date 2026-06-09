import SwiftUI
import UIKit

/// First-run setup wizard (and the gear-menu "Setup guide" replay). Full-screen, dark,
/// no nav chrome — a sequence of focused steps driven by ``OnboardingViewModel``.
///
/// `onFinished` hands the result back to ``RootView``: a non-nil ``TVDevice`` is the TV the
/// user just paired (persist it and open the remote); `nil` means "finished/skipped without a
/// new TV" (keep whatever was active, or drop to Discovery on first run).
@MainActor
struct OnboardingView: View {
    @State private var vm: OnboardingViewModel
    let onFinished: (TVDevice?) -> Void

    init(
        service: any TVService,
        discovery: any TVDiscoveryService,
        rememberedTVsStore: any RememberedTVsStore,
        isReplay: Bool,
        onFinished: @escaping (TVDevice?) -> Void
    ) {
        _vm = State(initialValue: OnboardingViewModel(
            service: service,
            discovery: discovery,
            rememberedTVsStore: rememberedTVsStore,
            isReplay: isReplay
        ))
        self.onFinished = onFinished
    }

    private var canSkip: Bool {
        switch vm.step {
        case .welcome, .network, .findTV: return true
        case .pair, .success, .test, .optimize: return false
        }
    }

    var body: some View {
        ZStack {
            RemoteTheme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                Group {
                    switch vm.step {
                    case .welcome:  WelcomeStep(vm: vm)
                    case .network:  NetworkStep(vm: vm)
                    case .findTV:   FindTVStep(vm: vm)
                    case .pair:     PairStep(vm: vm)
                    case .success:  SuccessStep(vm: vm)
                    case .test:     TestStep(vm: vm)
                    case .optimize: OptimizeStep(vm: vm, onDone: { onFinished(vm.selectedDevice) })
                    }
                }
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
        .animation(.snappy, value: vm.step)
    }

    private var header: some View {
        HStack {
            ProgressDots(current: vm.step)
            Spacer()
            if canSkip {
                Button("Skip") { onFinished(nil) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(height: 44)
        .padding(.top, 8)
    }
}

// MARK: - Progress

private struct ProgressDots: View {
    let current: OnboardingViewModel.Step

    var body: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingViewModel.Step.milestones, id: \.self) { milestone in
                Capsule()
                    .fill(isActive(milestone) ? Color.accentColor : Color.white.opacity(0.18))
                    .frame(width: isActive(milestone) ? 22 : 7, height: 7)
            }
        }
        .animation(.snappy, value: current)
    }

    /// Pair/success collapse onto the findTV dot so the bar doesn't jump during the
    /// transient pairing steps.
    private func isActive(_ milestone: OnboardingViewModel.Step) -> Bool {
        let effective: OnboardingViewModel.Step = {
            switch current {
            case .pair, .success: return .findTV
            default: return current
            }
        }()
        return milestone == effective
    }
}

// MARK: - Step scaffold

/// Shared layout: a big SF Symbol, title, subtitle, custom middle content, and a bottom
/// action area — keeps every step visually consistent.
private struct StepScaffold<Content: View, Actions: View>: View {
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

private struct PrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).bold().frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!enabled)
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    let vm: OnboardingViewModel
    var body: some View {
        StepScaffold(
            symbol: "appletvremote.gen4",
            title: "Welcome to RemoteTV",
            subtitle: "Turn your iPhone into a remote for your Samsung TV. Let's get you set up in a few quick steps."
        ) {
            EmptyView()
        } actions: {
            PrimaryButton(title: "Get Started") { Task { await vm.continueFromWelcome() } }
        }
    }
}

private struct NetworkStep: View {
    let vm: OnboardingViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        StepScaffold(
            symbol: vm.isOnWiFi ? "wifi" : "wifi.slash",
            symbolColor: vm.isOnWiFi ? .green : .yellow,
            title: "Join your TV's Wi-Fi",
            subtitle: "Your iPhone must be on the **same Wi-Fi network** as your TV — the remote talks to the TV directly and can't reach it over cellular."
        ) {
            VStack(spacing: 12) {
                statusRow
                if !vm.isOnWiFi {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(.subheadline.weight(.semibold))
                }
                Text("On first launch iOS will also ask for **Local Network** access — please allow it, or the remote can't find your TV.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            PrimaryButton(title: "Continue", enabled: vm.canAdvanceFromNetwork) {
                Task { await vm.continueFromNetwork() }
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: vm.isOnWiFi ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(vm.isOnWiFi ? .green : .yellow)
            Text(vm.isOnWiFi ? "Wi-Fi connected" : "Wi-Fi not connected")
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct FindTVStep: View {
    let vm: OnboardingViewModel

    var body: some View {
        StepScaffold(
            symbol: "tv",
            title: "Turn on your TV",
            subtitle: "Make sure your Samsung TV is powered on. We're scanning the network for it now."
        ) {
            VStack(spacing: 10) {
                if vm.discoveredTVs.isEmpty {
                    searchingOrEmpty
                } else {
                    ForEach(vm.discoveredTVs) { tv in
                        Button { Task { await vm.selectTV(tv) } } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "tv.fill").foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tv.friendlyName.isEmpty ? "Samsung TV" : tv.friendlyName)
                                        .bold().foregroundStyle(.white)
                                    Text(tv.ip).font(.caption).foregroundStyle(.white.opacity(0.5))
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.4))
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                manualEntry
            }
        } actions: {
            EmptyView()
        }
    }

    @ViewBuilder private var searchingOrEmpty: some View {
        if vm.searchTimedOut {
            VStack(spacing: 8) {
                Text("No TV found yet.").foregroundStyle(.white.opacity(0.8))
                Text("Check that the TV is on, on the same Wi-Fi (not a guest network), and that you allowed Local Network access. Then retry.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button("Retry scan") { Task { await vm.retrySearch() } }
                    .font(.subheadline.weight(.semibold)).padding(.top, 4)
            }
            .padding(14)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        } else {
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("Searching…").foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 20)
        }
    }

    @ViewBuilder private var manualEntry: some View {
        if vm.showManualEntry {
            HStack(spacing: 8) {
                TextField("TV IP address", text: Binding(get: { vm.manualIP }, set: { vm.manualIP = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                Button("Connect") { Task { await vm.useManualIP() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.manualIP.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 4)
        } else {
            Button("Enter IP manually") { vm.showManualEntry = true }
                .font(.footnote).foregroundStyle(.white.opacity(0.6))
                .padding(.top, 4)
        }
    }
}

private struct PairStep: View {
    let vm: OnboardingViewModel

    var body: some View {
        StepScaffold(
            symbol: vm.pairingFailed ? "exclamationmark.triangle.fill" : "hand.tap.fill",
            symbolColor: vm.pairingFailed ? .yellow : .accentColor,
            title: vm.pairingFailed ? "Couldn't connect" : "Allow on your TV",
            subtitle: subtitle
        ) {
            if !vm.pairingFailed, vm.connectionState != .connected {
                ProgressView().tint(.white).padding(.top, 4)
            }
        } actions: {
            VStack(spacing: 10) {
                if vm.pairingFailed {
                    PrimaryButton(title: "Try again") { Task { await vm.retryPairing() } }
                }
                Button("Pick a different TV") { Task { await vm.backToFind() } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var subtitle: String {
        if vm.pairingFailed {
            return "We reached \(vm.selectedDevice?.ip ?? "the TV") but pairing didn't complete. Make sure the TV is on, then try again — or pick a different TV."
        }
        switch vm.connectionState {
        case .awaitingPairing:
            return "Your TV is showing an **Allow** popup. Press **Allow** with the TV's physical remote to let RemoteTV control it."
        default:
            return "Connecting to \(vm.selectedDevice?.name ?? "your TV")…"
        }
    }
}

private struct SuccessStep: View {
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
            PrimaryButton(title: "Continue") { Task { await vm.continueFromSuccess() } }
                .padding(.bottom, 24)
        }
        .sensoryFeedback(.success, trigger: celebrate)
        .onAppear { celebrate = true }
    }
}

private struct TestStep: View {
    let vm: OnboardingViewModel

    var body: some View {
        StepScaffold(
            symbol: "speaker.wave.2.fill",
            title: "Test your remote",
            subtitle: "Let's make sure it works. Tap the button below — your TV's volume should go up."
        ) {
            VStack(spacing: 14) {
                Button { Task { await vm.sendTestKey() } } label: {
                    Label("Send Volume Up", systemImage: "plus")
                        .bold().frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)

                if vm.testResult == false {
                    Text("No response? Make sure the TV didn't go to sleep, and that you pressed **Allow** on it. You can still continue and try from the remote.")
                        .font(.footnote).foregroundStyle(.yellow.opacity(0.9))
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
            }
        } actions: {
            VStack(spacing: 10) {
                Text("Did the volume change?").foregroundStyle(.white.opacity(0.7)).font(.subheadline)
                HStack(spacing: 12) {
                    Button("No") { vm.recordTestResult(false) }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity)
                    Button("Yes 🎉") {
                        vm.recordTestResult(true)
                        Task { await vm.continueFromTest() }
                    }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                }
                if vm.testResult == false {
                    Button("Continue anyway") { Task { await vm.continueFromTest() } }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }
}

private struct OptimizeStep: View {
    let vm: OnboardingViewModel
    let onDone: () -> Void

    var body: some View {
        StepScaffold(
            symbol: "gearshape.2.fill",
            title: "Optimize your TV",
            subtitle: "Two optional TV settings make the remote much nicer to live with. (Exact menu names vary a little by model year.)"
        ) {
            VStack(spacing: 12) {
                SettingCard(
                    icon: "bell.slash.fill",
                    title: "Stop the repeated “Allow” prompts",
                    lines: [
                        "Settings → General → External Device Manager",
                        "→ Device Connect Manager → Access Notification",
                        "Set to “First Time Only” (and check this phone is in Device List → Allowed)."
                    ]
                )
                SettingCard(
                    icon: "power",
                    title: "Let the remote wake the TV (Wake-on-LAN)",
                    lines: [
                        "Settings → General → Network → Expert Settings",
                        "Turn on “Power On with Mobile” and “IP Remote”.",
                        "Keep “Network Standby” on so the TV can wake from standby."
                    ]
                )
            }
        } actions: {
            PrimaryButton(title: vm.isReplay ? "Done" : "Start using the remote", action: onDone)
        }
    }
}

private struct SettingCard: View {
    let icon: String
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Success animation

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
