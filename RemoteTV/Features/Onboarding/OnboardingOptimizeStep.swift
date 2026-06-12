import SwiftUI

struct OnboardingOptimizeStep: View {
    let vm: OnboardingViewModel
    let onDone: () -> Void

    var body: some View {
        OnboardingStepScaffold(
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
            OnboardingPrimaryButton(title: vm.isReplay ? "Done" : "Start using the remote", action: onDone)
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
