import SwiftUI

struct OnboardingFindTVStep: View {
    let vm: OnboardingViewModel

    var body: some View {
        OnboardingStepScaffold(
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
                    if vm.isSearching {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(.white)
                            Text("Searching for more TVs…")
                                .font(.caption).foregroundStyle(.white.opacity(0.6))
                        }
                        .padding(.top, 2)
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
