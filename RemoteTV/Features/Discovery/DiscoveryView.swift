import SwiftUI

@MainActor
struct DiscoveryView: View {
    let service: any TVService
    @State private var viewModel: DiscoveryViewModel
    @State private var showPowerOnHelp: Bool = false
    @AppStorage("lastConnectionMode") private var storedMode: String = TVConnectionMode.plain.rawValue
    /// JSON-encoded ``TVDevice`` of the last TV the user navigated into, persisted
    /// across launches so the app can relaunch straight into ``RemoteView`` for that
    /// TV. Empty string means "no stored device — start at Discovery." The value is
    /// kept in sync by the `onChange(of: viewModel.path)` observer below: any push
    /// stores the topmost device, any pop (Disconnect, Forget, system back) clears it.
    @AppStorage("lastRemoteDeviceJSON") private var lastRemoteDeviceJSON: String = ""

    init(
        service: any TVService,
        discovery: any TVDiscoveryService,
        rememberedTVsStore: any RememberedTVsStore,
        wakeService: (any WakeOnLANService)? = nil
    ) {
        self.service = service
        _viewModel = State(initialValue: DiscoveryViewModel(
            discovery: discovery,
            rememberedStore: rememberedTVsStore,
            wakeService: wakeService
        ))
    }

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            ZStack {
                content
            }
            .navigationTitle("RemoteTV")
            .navigationDestination(for: TVDevice.self) { device in
                RemoteView(device: device, service: service)
            }
            .toolbar { toolbar }
            .sheet(isPresented: $showPowerOnHelp) {
                PowerOnHelpSheet()
                    .presentationDetents([.medium])
            }
        }
        .task {
            restoreStoredMode()
            await viewModel.loadRemembered()
            restoreLastRemoteDevice()
        }
        .onChange(of: viewModel.mode) { _, newValue in
            storedMode = newValue.rawValue
        }
        .onChange(of: viewModel.path) { _, newPath in
            persistLastRemoteDevice(newPath.last)
        }
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
                        onConnect: viewModel.connectToManualIP
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

    /// Re-pushes the last TV onto the navigation path so the user lands directly in
    /// ``RemoteView`` after a relaunch. Bails if the path is already non-empty (e.g.
    /// `.task` re-fired after a navigation that's already in flight) or the stored
    /// JSON is malformed — the latter clears the slot so a corrupt entry doesn't
    /// hijack every future launch.
    private func restoreLastRemoteDevice() {
        guard viewModel.path.isEmpty, !lastRemoteDeviceJSON.isEmpty else { return }
        let data = Data(lastRemoteDeviceJSON.utf8)
        guard let device = try? JSONDecoder().decode(TVDevice.self, from: data) else {
            lastRemoteDeviceJSON = ""
            return
        }
        viewModel.path.append(device)
    }

    /// Mirrors the topmost path entry into `@AppStorage`. Called from the path
    /// observer on every push and pop, so disconnecting / forgetting / using the
    /// system back gesture all clear the stored device automatically — no separate
    /// teardown wiring needed in the toolbar handlers.
    private func persistLastRemoteDevice(_ device: TVDevice?) {
        guard let device else {
            lastRemoteDeviceJSON = ""
            return
        }
        guard
            let data = try? JSONEncoder().encode(device),
            let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        lastRemoteDeviceJSON = json
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

private struct PowerOnHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("If Power On isn't working") {
                    Text("Samsung TVs only listen for Wake-on-LAN packets when Network Standby is enabled.")
                    Text("Turn the TV on and go to Settings → General → Network → Expert Settings → Power On with Mobile, then enable it.")
                    Text("You may also need to enable IP Remote in the same menu.")
                }
                Section("First-time setup") {
                    Text("Connect to the TV at least once while it's on. The app captures its MAC address on that first connect, which is what the magic packet needs.")
                }
            }
            .navigationTitle("Power On Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
