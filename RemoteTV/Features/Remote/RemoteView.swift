import SwiftUI

/// Samsung-style remote screen. Lays out the same fixed dark canvas as
/// `RemoteSamsungStyleView` and uniformly scales it via `GeometryReader` so the
/// design fills any device without distortion.
///
/// The screen is split into up to two columns by an `HStack`:
/// * **Left column** — the optional Installed Apps panel (when ``SidePanelMode/installedApps``).
/// * **Centre / right column** — the remote canvas itself. Scales to fill whatever
///   width the `HStack` hands it, so toggling a panel automatically halves the
///   remote's space without any explicit per-device math.
/// * **Right column** — the optional Sniff Log panel (when ``SidePanelMode/sniffLog``).
///
/// The two side panels are mutually exclusive. All view options — input mode,
/// side-panel choice, Disconnect, Forget — live in the gear menu in the navigation
/// toolbar.
@MainActor
struct RemoteView: View {
    @State private var viewModel: RemoteViewModel
    /// Persisted across launches so the user only picks D-Pad vs Trackpad once.
    @AppStorage("remoteInputMode") private var inputMode: RemoteInputMode = .dpad
    /// Persisted across launches; default is no side panel so first-run users see
    /// the remote at full size.
    @AppStorage("remoteSidePanel") private var sidePanel: SidePanelMode = .none
    @Environment(\.dismiss) private var dismiss

    /// Virtual canvas dimensions. Matches `RemoteSamsungStyleView`'s 393×852 — the
    /// extras strip from the previous iteration is gone now that the picker lives
    /// in the gear menu and the installed-apps loader lives in its own side panel.
    private let canvasWidth: CGFloat = 393*0.8
    private let canvasHeight: CGFloat = 852*0.8
    private let bodyTop: CGFloat = 80
    private let bodyHeight: CGFloat = RemoteSamsungBody.height
    private let bodyWidth: CGFloat = RemoteSamsungBody.width
    private var bodyLeading: CGFloat { (canvasWidth - bodyWidth) / 2 }

    init(device: TVDevice, service: any TVService) {
        _viewModel = State(initialValue: RemoteViewModel(device: device, service: service))
    }

    var body: some View {
        ZStack {
            RemoteTheme.bg.ignoresSafeArea()

            HStack(spacing: 0) {
                if sidePanel == .shortcuts {
                    RemoteSidePanelShortcuts(onLaunch: viewModel.launchApp)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                if sidePanel == .installedApps {
                    RemoteSidePanelInstalledApps(
                        installedApps: viewModel.installedApps,
                        isLoading: viewModel.isLoadingInstalledApps,
                        onRefresh: viewModel.refreshInstalledApps,
                        onLaunch: viewModel.launchApp
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                GeometryReader { geo in
                    let scale = min(geo.size.width / canvasWidth, geo.size.height / canvasHeight)
                    ZStack(alignment: .topLeading) {
                        CompactCommercialMute(
                            remaining: viewModel.commercialMuteRemaining,
                            onToggle: viewModel.toggleCommercialMute
                        )
                        .frame(width: 100)
                        .position(x: 16 + 50, y: 82)

                        RemoteSamsungBody(
                            state: viewModel.state,
                            hasError: viewModel.lastError != nil,
                            inputMode: inputMode,
                            installedApps: viewModel.installedApps,
                            onCommand: viewModel.send,
                            onLiveTV: viewModel.goLive,
                            onLaunchApp: viewModel.launchApp
                        )
                        .frame(width: bodyWidth, height: bodyHeight)
                        .offset(x: bodyLeading, y: bodyTop)
                    }
                    .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
                    .scaleEffect(scale)
                    .frame(width: canvasWidth * scale, height: canvasHeight * scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if sidePanel == .sniffLog {
                    RemoteSidePanelSniffLog(
                        entries: viewModel.sniffLog,
                        onClear: viewModel.clearSniffLog
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: sidePanel)
           
        }
        .navigationTitle(viewModel.device.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Input mode", selection: $inputMode) {
                        ForEach(RemoteInputMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)

                    Picker("Side panel", selection: $sidePanel) {
                        ForEach(SidePanelMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)

                    Divider()

                    Button("Disconnect & switch mode", systemImage: "arrow.left.arrow.right") {
                        Task {
                            await viewModel.disconnect()
                            dismiss()
                        }
                    }
                    Button("Forget this TV", systemImage: "trash", role: .destructive) {
                        Task {
                            await viewModel.forgetTV()
                            dismiss()
                        }
                    }
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .task {
            await viewModel.connect()
        }
    }
}
