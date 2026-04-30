import SwiftUI

@MainActor
struct RemoteView: View {
    @State private var viewModel: RemoteViewModel
    /// Persisted across launches so the user only picks D-Pad vs Trackpad once.
    /// Same convention as `lastConnectionMode` (see project notes).
    @AppStorage("remoteInputMode") private var inputMode: RemoteInputMode = .dpad
    @Environment(\.dismiss) private var dismiss

    init(device: TVDevice, service: any TVService) {
        _viewModel = State(initialValue: RemoteViewModel(device: device, service: service))
    }

    var body: some View {
        ScrollView {
            VStack {
                StatusPill(state: viewModel.state, mode: viewModel.mode)
                CommercialMuteSection(
                    remaining: viewModel.commercialMuteRemaining,
                    onToggle: viewModel.toggleCommercialMute
                )
                Spacer()
                Picker("Input mode", selection: $inputMode) {
                    ForEach(RemoteInputMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                switch inputMode {
                case .dpad:
                    DPadSection(onCommand: viewModel.send)
                case .trackpad:
                    TrackpadSection(onCommand: viewModel.send)
                }
                Spacer()
                VolumeSection(onCommand: viewModel.send)
                Spacer()
                ChannelSection(onCommand: viewModel.send)
                Spacer()
                AppsSection(onLaunch: viewModel.launchApp)
                Spacer()
                InstalledAppsSection(
                    installedApps: viewModel.installedApps,
                    isLoading: viewModel.isLoadingInstalledApps,
                    onRefresh: viewModel.refreshInstalledApps,
                    onLaunch: viewModel.launchApp
                )
                Spacer()
                BottomActionsSection(
                    onCommand: viewModel.send,
                    onLiveTV: viewModel.goLive
                )
                Spacer()
                SniffLogSection(
                    entries: viewModel.sniffLog,
                    onClear: viewModel.clearSniffLog
                )
                if let error = viewModel.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .navigationTitle(viewModel.device.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.connect()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RemoteToolbarMenu(
                    onDisconnect: {
                        Task {
                            await viewModel.disconnect()
                            dismiss()
                        }
                    },
                    onForget: {
                        Task {
                            await viewModel.forgetTV()
                            dismiss()
                        }
                    }
                )
            }
        }
    }
}
