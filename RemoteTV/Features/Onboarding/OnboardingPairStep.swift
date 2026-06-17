import SwiftUI

struct OnboardingPairStep: View {
    let vm: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(
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
                    OnboardingPrimaryButton(title: "Try again") { Task { await vm.retryPairing() } }
                }
                Button("Pick a different TV") { Task { await vm.backToFind() } }
                    .buttonStyle(OnboardingLinkButtonStyle())
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
