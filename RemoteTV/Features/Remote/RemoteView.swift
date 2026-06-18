import RemoteTVCore
import SwiftUI

/// Samsung-style remote screen. Lays out a fixed dark canvas (composed from the
/// design atoms in `RemoteSamsungStyle.swift`) and uniformly scales it via
/// `GeometryReader` so the design fills any device without distortion.
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
    /// Set by the "Setup guide" menu item to replay onboarding; ``RootView`` watches the
    /// same key and presents the wizard over the remote.
    @AppStorage("onboardingReplayRequested") private var onboardingReplayRequested = false
    /// Drives the modal `PowerOnHelpSheet` that the power button's long-press in
    /// wake mode presents — explains why a magic packet might not be reaching the
    /// TV (Network Standby disabled, MAC missing, etc.).
    @State private var showPowerOnHelp: Bool = false
    /// Drives the push navigation to the full TV Guide screen (toolbar button + the
    /// "Now on TV" pill both set this).
    @State private var showTVGuide: Bool = false
    /// Presents the on-screen keyboard relay from the gear menu.
    @State private var showKeyboard: Bool = false
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

    /// Inter-key delay for tune macros. Tizen drops digits when they arrive faster than
    /// ~80 ms apart on this generation of TVs (same gating the physical remote uses
    /// internally). 120 ms is comfortable headroom and still feels instant.
    private static let tuneInterKeyDelay: Duration = .milliseconds(120)

    /// Dispatches a multi-key macro (e.g. the digits + Enter to tune to a channel)
    /// through the remote view-model. Awaits each command before sending the next so
    /// the TV sees a clean digit sequence rather than a racing batch.
    private func dispatchTuneMacro(_ commands: [TVCommand]) async {
        for (index, command) in commands.enumerated() {
            await viewModel.send(command)
            if index < commands.count - 1 {
                try? await Task.sleep(for: Self.tuneInterKeyDelay)
            }
        }
    }

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

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                if sidePanel == .shortcuts {
                    RemoteSidePanelShortcuts(
                        onLaunch: viewModel.launchApp,
                        onCastYouTube: { await viewModel.castYouTube() }
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                #if DEBUG
                // Developer tool — only available in debug builds.
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
                #endif

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
                            onMicDown: { Task { await viewModel.startVoice() } },
                            onMicUp: { Task { await viewModel.stopVoice() } },
                            powerMode: viewModel.isInWakeMode ? .wake : .standby,
                            onPowerTap: { Task { await viewModel.handlePowerTap() } },
                            onPowerLongPress: {
                                if viewModel.isInWakeMode {
                                    showPowerOnHelp = true
                                } else {
                                    Task { await viewModel.send(.sleepTimer) }
                                }
                            },
                            isMuted: viewModel.isMuted,
                            muteRemaining: viewModel.commercialMuteRemaining,
                            muteTotalSeconds: viewModel.commercialMuteTotalSeconds,
                            onToggleMute: { Task { await viewModel.toggleMute() } },
                            onScheduleUnmute: { seconds in
                                Task { await viewModel.scheduleUnmute(after: seconds) }
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

                #if DEBUG
                // Developer tool — only available in debug builds.
                if sidePanel == .sniffLog {
                    RemoteSidePanelSniffLog(
                        entries: viewModel.sniffLog,
                        onClear: viewModel.clearSniffLog,
                        probes: RemoteViewModel.bixbyProbes,
                        onProbe: { probe in Task { await viewModel.runProbe(probe) } },
                        onSendText: { Task { await viewModel.sendTestText() } }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                #endif

                // TV Guide is presented full-screen (see `.fullScreenCover` below), not as a
                // side column — it's a browsing surface that wants the whole screen.
            }
            .animation(.snappy, value: sidePanel)
            // "Now on TV" pill — always shown. With a pinned channel it surfaces what's on
            // now and opens that channel's schedule; otherwise it's a "Check out TV Guide"
            // prompt that opens the main guide. Floated as a top overlay (rather than
            // stacked above the remote) so it occupies the empty space above the remote
            // body instead of shrinking the height-constrained remote canvas.
            .overlay(alignment: .top) {
                NowOnTVPill(
                    channel: epgViewModel.pinnedChannel,
                    programme: epgViewModel.pinnedNowPlaying,
                    onTap: {
                        // Pinned → open that channel's schedule; otherwise the main list.
                        epgViewModel.selectedChannelID = epgViewModel.pinnedChannel?.id
                        showTVGuide = true
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            }  // close outer VStack added for the NowOnTVPill
            .animation(.snappy, value: epgViewModel.pinnedChannelID)
            .task {
                // Pre-warm the EPG so the pinned-channel pill can populate immediately
                // on first launch (otherwise the pill would render with no programme
                // data until the user opened the TV Guide panel).
                if epgViewModel.pinnedChannelID != nil {
                    await epgViewModel.loadIfNeeded()
                }
            }
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
//            ToolbarItem(placement: .topBarTrailing) {
//                Button {
//                    showTVGuide = true
//                } label: {
//                    Label("TV Guide", systemImage: "tv")
//                }
//                .accessibilityLabel("Open TV Guide")
//            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Input mode", selection: $inputMode) {
                        ForEach(RemoteInputMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)

                    Picker("Side panel", selection: $sidePanel) {
                        ForEach(SidePanelMode.selectableCases) { mode in
                            Label(mode.label, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)

                    Divider()

                    Button("Keyboard", systemImage: "keyboard") {
                        showKeyboard = true
                    }
                    Button("Setup guide", systemImage: "sparkles") {
                        onboardingReplayRequested = true
                    }
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
        .sheet(isPresented: $showKeyboard) {
            KeyboardInputView(
                onType: { await viewModel.sendKeyboardText($0) },
                onSubmit: { await viewModel.send(.enter) }
            )
        }
        .navigationDestination(isPresented: $showTVGuide) {
            // The guide's channel list and a channel's schedule are each real navigation
            // entries (the schedule is pushed via `navigationDestination(item:)` inside
            // `RemoteSidePanelEPG`), so both levels keep the native back button and
            // left-edge swipe-to-go-back.
            RemoteSidePanelEPG(vm: epgViewModel, onDispatchMacro: dispatchTuneMacro)
                .navigationTitle("TV Guide")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.visible, for: .navigationBar)
        }
        }
        // Tint nav-bar icons + back buttons (RemoteView's toolbar and the pushed
        // TV Guide / schedule) with the app accent. Inner controls keep their explicit
        // tints, so only the otherwise-default-blue bar items pick this up.
        .tint(RemoteTheme.accent)
    }
}
