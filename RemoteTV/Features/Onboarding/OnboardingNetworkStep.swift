import SwiftUI
import UIKit

struct OnboardingNetworkStep: View {
    let vm: OnboardingViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        OnboardingStepScaffold(
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
                    .buttonStyle(OnboardingLinkButtonStyle(prominent: true))
                }
                Text("On first launch iOS will also ask for **Local Network** access — please allow it, or the remote can't find your TV.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            OnboardingPrimaryButton(title: "Continue", enabled: vm.canAdvanceFromNetwork) {
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
