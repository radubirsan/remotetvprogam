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
    /// Held at this level so the on-disk-cached `EPGGuide` survives the user toggling
    /// the TV-guide side panel on and off — `EPGViewModel` owns the `EPGClient` whose
    /// in-memory cache would otherwise be lost on every panel close.
    @State private var epgViewModel = EPGViewModel()
    /// Hand-off to the parent ``RootView`` when the user picks *Disconnect & switch
    /// mode* or *Forget this TV* from the gear menu — clearing the active-device
    /// slot is the only way the app surfaces Discovery again, since there is no
    /// back button.
    let onDisconnect: () -> Void
    /// Persisted across launches so the user only picks D-Pad vs Trackpad once.
    @AppStorage("remoteInputMode") private var inputMode: RemoteInputMode = .dpad
    /// Persisted across launches; default is no side panel so first-run users see
    /// the remote at full size.
    @AppStorage("remoteSidePanel") private var sidePanel: SidePanelMode = .none
    /// Drives the modal `PowerOnHelpSheet` that the power button's long-press in
    /// wake mode presents — explains why a magic packet might not be reaching the
    /// TV (Network Standby disabled, MAC missing, etc.).
    @State private var showPowerOnHelp: Bool = false
    /// Lets us auto-recover the WebSocket when the user unlocks the phone or returns
    /// from the app switcher — iOS suspends URLSession traffic in the background and
    /// the TV closes idle sockets, so the remote screen on resume needs an explicit
    /// re-handshake to keep working without the user backing out and re-entering.
    @Environment(\.scenePhase) private var scenePhase

    /// Virtual canvas dimensions. Width matches the design's 393pt iPhone canvas;
    /// height bumped to 940 to accommodate the +25%-scaled remote body (880 tall
    /// instead of 760). The +10% canvas height ratio versus the +25% button growth
    /// is intentional — `GeometryReader` scales the canvas to fit, so a smaller
    /// canvas-height bump means the buttons render visibly larger on iPhone.
    private let canvasWidth: CGFloat = 393
    private let canvasHeight: CGFloat = 940
    private let bodyTop: CGFloat = 60
    private let bodyHeight: CGFloat = RemoteSamsungBody.height
    private let bodyWidth: CGFloat = RemoteSamsungBody.width
    private var bodyLeading: CGFloat { (canvasWidth - bodyWidth) / 2 }

    init(
        device: TVDevice,
        service: any TVService,
        wakeService: (any WakeOnLANService)? = nil,
        rememberedTVsStore: (any RememberedTVsStore)? = nil,
        onDisconnect: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: RemoteViewModel(
            device: device,
            service: service,
            wakeService: wakeService,
            rememberedTVsStore: rememberedTVsStore
        ))
        self.onDisconnect = onDisconnect
    }

    var body: some View {
        // Wrapped in `NavigationStack` because `RemoteView` is now installed as a
        // root view by ``RootView`` rather than pushed onto the discovery stack —
        // the toolbar and `.navigationTitle` need a stack ancestor to render.
        NavigationStack {
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
                        RemoteSamsungBody(
                            state: viewModel.state,
                            powerState: viewModel.tvPowerState,
                            hasError: viewModel.lastError != nil,
                            inputMode: inputMode,
                            installedApps: viewModel.installedApps,
                            onCommand: viewModel.send,
                            onLiveTV: viewModel.goLive,
                            onLaunchApp: viewModel.launchApp,
                            powerMode: viewModel.isInWakeMode ? .wake : .standby,
                            onPowerTap: { Task { await viewModel.handlePowerTap() } },
                            onPowerLongPress: {
                                if viewModel.isInWakeMode {
                                    showPowerOnHelp = true
                                } else {
                                    Task { await viewModel.send(.sleepTimer) }
                                }
                            }
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

                if sidePanel == .tvGuide {
                    RemoteSidePanelEPG(vm: epgViewModel)
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
            ToolbarItem(placement: .topBarLeading) {
                CompactCommercialMute(
                    remaining: viewModel.commercialMuteRemaining,
                    onToggle: viewModel.toggleCommercialMute
                )
            }
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
                            onDisconnect()
                        }
                    }
                    Button("Forget this TV", systemImage: "trash", role: .destructive) {
                        Task {
                            await viewModel.forgetTV()
                            onDisconnect()
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
        .onChange(of: scenePhase) { oldPhase, newPhase in
            guard newPhase == .active, oldPhase != .active else { return }
            Task { await viewModel.reconnectIfNeeded() }
        }
        .sheet(isPresented: $showPowerOnHelp) {
            PowerOnHelpSheet()
                .presentationDetents([.medium])
        }
        }
    }
}
