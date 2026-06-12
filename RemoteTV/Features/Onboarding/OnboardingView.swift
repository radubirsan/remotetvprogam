import SwiftUI

/// First-run setup wizard (and the gear-menu "Setup guide" replay). Full-screen, dark,
/// no nav chrome — a sequence of focused steps driven by ``OnboardingViewModel``.
/// Each step's body lives in its own `Onboarding…Step.swift` file; the shared chrome
/// (symbol/title/subtitle/actions layout) is ``OnboardingStepScaffold``.
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
                    case .welcome:  OnboardingWelcomeStep(vm: vm)
                    case .network:  OnboardingNetworkStep(vm: vm)
                    case .findTV:   OnboardingFindTVStep(vm: vm)
                    case .pair:     OnboardingPairStep(vm: vm)
                    case .success:  OnboardingSuccessStep(vm: vm)
                    case .test:     OnboardingTestStep(vm: vm)
                    case .optimize: OnboardingOptimizeStep(vm: vm, onDone: { onFinished(vm.selectedDevice) })
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
