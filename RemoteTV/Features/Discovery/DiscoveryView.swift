import SwiftUI

@MainActor
struct DiscoveryView: View {
    let service: any TVService
    /// Hand-off to the parent ``RootView`` when the user picks a TV — the parent
    /// flips its `@AppStorage` slot and re-renders, swapping this view out for the
    /// remote. There is no navigation push here on purpose: returning to Discovery
    /// is intentionally a one-way trip from the gear menu, not a back-button affair.
    let onConnect: (TVDevice) -> Void
    @State private var viewModel: DiscoveryViewModel
    @State private var showPowerOnHelp: Bool = false
    @AppStorage("lastConnectionMode") private var storedMode: String = TVConnectionMode.plain.rawValue

    init(
        service: any TVService,
        discovery: any TVDiscoveryService,
        rememberedTVsStore: any RememberedTVsStore,
        wakeService: (any WakeOnLANService)? = nil,
        onConnect: @escaping (TVDevice) -> Void
    ) {
        self.service = service
        self.onConnect = onConnect
        _viewModel = State(initialValue: DiscoveryViewModel(
            discovery: discovery,
            rememberedStore: rememberedTVsStore,
            wakeService: wakeService
        ))
    }

    var body: some View {
        // Plain `NavigationStack` (no path binding) — Discovery has no child routes
        // anymore; the TV-picked transition is handled by the parent ``RootView``
        // swapping this view out wholesale. The stack is kept solely to host the
        // navigation bar and the Search/Stop toolbar.
        NavigationStack {
            ZStack {
                content
            }
            .navigationTitle("RemoteTV")
            .toolbar { toolbar }
            .sheet(isPresented: $showPowerOnHelp) {
                PowerOnHelpSheet()
                    .presentationDetents([.medium])
            }
        }
        .task {
            restoreStoredMode()
            await viewModel.loadRemembered()
        }
        .onChange(of: viewModel.mode) { _, newValue in
            storedMode = newValue.rawValue
        }
    }

    /// Bridges the manual-connect button in ``ManualConnectRow`` (which only knows
    /// `() -> Void`) to the typed `onConnect` callback the parent expects.
    private func connectManualIP() {
        guard let device = viewModel.makeManualDevice() else { return }
        onConnect(device)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.showEmptyState {
            EmptyStateView(
                onRetry: { Task { await viewModel.refresh() } },
                onHelp: { showPowerOnHelp = true },
                onBack: { viewModel.dismissEmptyState() }
            )
        } else {
            List {
                Section {
                    Picker("Mode", selection: $viewModel.mode) {
                        Text("Plain (8001)").tag(TVConnectionMode.plain)
                        Text("Secure (8002)").tag(TVConnectionMode.secure)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Connect by IP") {
                    ManualConnectRow(
                        ip: $viewModel.manualIP,
                        onConnect: { connectManualIP() }
                    )
                }

                Section {
                    if viewModel.rows.isEmpty {
                        DiscoveryPlaceholderRow(isSearching: viewModel.isSearching)
                    } else {
                        ForEach(viewModel.rows) { row in
                            Button {
                                viewModel.manualIP = row.ip
                            } label: {
                                TVListRow(
                                    row: row,
                                    isWaking: viewModel.wakingRowID == row.id,
                                    onWake: { Task { await viewModel.wake(row) } }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Discovered")
                } footer: {
                    if let message = viewModel.errorMessage {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if viewModel.isSearching {
                Button("Stop", systemImage: "stop.circle") {
                    Task { await viewModel.stop() }
                }
            } else {
                Button("Search", systemImage: "magnifyingglass") {
                    Task { await viewModel.start() }
                }
            }
        }
    }

    private func restoreStoredMode() {
        if let stored = TVConnectionMode(rawValue: storedMode) {
            viewModel.mode = stored
        }
    }
}

private struct DiscoveryPlaceholderRow: View {
    let isSearching: Bool

    var body: some View {
        HStack {
            if isSearching {
                ProgressView()
                Text("Searching for TVs…")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("Tap Search to find TVs on your network.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ManualConnectRow: View {
    @Binding var ip: String
    let onConnect: () -> Void

    var body: some View {
        HStack {
            TextField("192.168.1.100", text: $ip)
                .keyboardType(.numbersAndPunctuation)
                .textContentType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.go)
                .onSubmit(onConnect)
            Button("Connect", systemImage: "arrow.right.circle.fill", action: onConnect)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .disabled(ip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

private struct EmptyStateView: View {
    let onRetry: () -> Void
    let onHelp: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack {
            ContentUnavailableView(
                "No TVs found",
                systemImage: "tv.slash",
                description: Text("Check that the TV is powered on and on the same Wi-Fi network.")
            )
            Button("Try Again", systemImage: "arrow.clockwise", action: onRetry)
                .buttonStyle(.borderedProminent)
            Button("Power On not working?", systemImage: "questionmark.circle", action: onHelp)
                .buttonStyle(.bordered)
            Button("Back", systemImage: "chevron.left", action: onBack)
                .buttonStyle(.bordered)
        }
        .padding()
    }
}

// `PowerOnHelpSheet` lives in `Features/Remote/PowerOnHelpSheet.swift` and is shared
// with the remote screen's power-button long-press when in wake mode.
