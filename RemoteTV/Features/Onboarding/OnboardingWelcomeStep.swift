import SwiftUI

struct OnboardingWelcomeStep: View {
    let vm: OnboardingViewModel
    var body: some View {
        OnboardingStepScaffold(
            symbol: "appletvremote.gen4",
            title: "Welcome to RemoteTV",
            subtitle: "Turn your iPhone into a remote for your Samsung TV. Let's get you set up in a few quick steps."
        ) {
            EmptyView()
        } actions: {
            OnboardingPrimaryButton(title: "Get Started") { Task { await vm.continueFromWelcome() } }
        }
    }
}
