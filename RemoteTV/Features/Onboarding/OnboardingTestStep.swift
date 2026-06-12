import SwiftUI

struct OnboardingTestStep: View {
    let vm: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(
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
