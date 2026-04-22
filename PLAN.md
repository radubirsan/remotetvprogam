# Samsung TV Remote — POC Plan

## Scope (POC boundary)
- TVs **discovered automatically via Bonjour/mDNS** (`NWBrowser`) — no manual IP entry
  - Browse the `_samsungmsf._tcp` service type (Samsung Multiscreen Framework — advertised by every powered-on Tizen TV)
  - TXT record carries `u` (UDN), `md` (model), `fn` (friendly name); short-lived `NWConnection` resolves each result's endpoint to a concrete IP
  - Requires only `NSBonjourServices` + `NSLocalNetworkUsageDescription` in Info.plist — **no multicast entitlement needed** (the OS-managed mDNS responder handles multicast for us)
- **Both connection modes** supported and switchable from the UI:
  - `ws://<ip>:8001/api/v2/channels/samsung.remote.control` (plain, older TVs ~2016–2018)
  - `wss://<ip>:8002/api/v2/channels/samsung.remote.control` (secure, 2019+ TVs)
  - Self-signed TV cert trusted via a custom `URLSessionDelegate` — **not App Store safe**, acceptable for POC
- **Token persisted in Keychain, keyed by TV UDN** — pairing popup only appears on first successful connect; subsequent launches reconnect silently (UDN chosen over IP because IP changes on DHCP renewal)
- **Power On via Wake-on-LAN** — magic packet UDP-broadcast to `255.255.255.255:9`
  - TV's MAC captured on first successful connect via `GET http://<ip>:8001/api/v2/` REST probe (`device.wifiMac`) and persisted
  - Non-secret TV metadata (UDN, name, model, lastIP, mac) lives in a JSON file in `URL.documentsDirectory`; only the auth token stays in Keychain
  - Uses existing Local Network permission — **no multicast entitlement needed** (broadcast ≠ multicast)
  - Requires user to have enabled "Network Standby" / "Power On with Mobile" in the TV (documented in the in-app empty state)
- Buttons: D-pad, OK/Back, Vol ±/Mute, Home, Power Off (Power On is surfaced in `DiscoveryView` for remembered-but-off TVs, not on the remote itself)
- iPhone portrait, iOS 26+, Swift 6.2, no third-party deps

Explicitly **out of POC** → Phase 2: app launch, reconnection, iPad.

## Project layout (`~/Desktop/remotetv/RemoteTV.xcodeproj`)
```
RemoteTV/
  App/RemoteTVApp.swift
  Domain/
    TVCommand.swift           // enum: .volumeUp, .up, .enter, .powerOff, …
    TVConnectionMode.swift    // .plain (ws:8001) | .secure (wss:8002)
    TVConnectionState.swift   // .disconnected | .connecting | .awaitingPairing | .connected | .failed(Error)
    TVDevice.swift            // udn, ip, name, mode
    RememberedTV.swift        // udn, friendlyName, modelName, lastIP, mac?
  Services/
    TVService.swift           // protocol
    SamsungTVService.swift    // URLSessionWebSocketTask impl, @Observable @MainActor
    SamsungTrustDelegate.swift // URLSessionDelegate — accepts self-signed cert for .secure
    TVCommandEncoder.swift    // TVCommand → JSON payload
    TVURLBuilder.swift        // device + app-name + optional token → URL
    TVTokenStore.swift        // protocol — load / save / delete token per TV (keyed by UDN)
    KeychainTVTokenStore.swift // Keychain impl, kSecAttrAccessibleAfterFirstUnlock, account = UDN
    RememberedTVsStore.swift  // protocol — all / upsert / delete non-secret TV records
    FileRememberedTVsStore.swift // JSON file in URL.documentsDirectory
    SamsungDeviceInfoService.swift // GET http://<ip>:8001/api/v2/ → parses wifiMac/name/model
    WakeOnLANService.swift    // protocol — wake(mac:) async throws
    UDPBroadcastWakeService.swift // NWConnection UDP broadcast to 255.255.255.255:9, 3 bursts
    MagicPacketBuilder.swift  // "AA:BB:CC:DD:EE:FF" → 6×0xFF + MAC×16 (102 bytes)
  Discovery/
    DiscoveredTV.swift                 // ip, friendlyName, modelName, udn
    TVDiscoveryService.swift           // protocol — discoveries() -> AsyncStream, start/stop
    BonjourDiscoveryService.swift      // NWBrowser over _samsungmsf._tcp, TXT-record parsing, endpoint resolve
  Features/
    Discovery/DiscoveryView.swift + DiscoveryViewModel.swift + TVListRow.swift
    Remote/RemoteView.swift + RemoteViewModel.swift + RemoteButton.swift
  Resources/Localizable.xcstrings
  Tests/ (Swift Testing)
    TVCommandEncoderTests.swift
    TVURLBuilderTests.swift      // asserts scheme/port/token param per mode
    TVTokenStoreTests.swift      // round-trip save / load / delete via in-memory fake
    RememberedTVsStoreTests.swift // JSON round-trip, upsert-by-udn, delete semantics
    MagicPacketBuilderTests.swift // valid/invalid MAC strings; exact 102-byte layout
    SamsungDeviceInfoServiceTests.swift // fake URLProtocol → decoded wifiMac/name/model
    DiscoveryViewModelTests.swift          // fake TVDiscoveryService stream → dedupe/ordering
    RemoteViewModelTests.swift   // fake TVService + fake TVTokenStore
```

## Core types

```swift
enum TVCommand: String, CaseIterable, Sendable {
    case volumeUp = "KEY_VOLUP", volumeDown = "KEY_VOLDOWN", mute = "KEY_MUTE"
    case up = "KEY_UP", down = "KEY_DOWN", left = "KEY_LEFT", right = "KEY_RIGHT"
    case enter = "KEY_ENTER", back = "KEY_RETURN", home = "KEY_HOME"
    case powerOff = "KEY_POWER"
}

enum TVConnectionMode: String, CaseIterable, Identifiable, Sendable {
    case plain   // ws://<ip>:8001
    case secure  // wss://<ip>:8002
    var id: String { rawValue }
    var scheme: String { self == .secure ? "wss" : "ws" }
    var port: Int    { self == .secure ? 8002 : 8001 }
}

struct TVDevice: Sendable, Hashable, Identifiable {
    var id: String { udn }
    var udn: String
    var ip: String
    var name: String
    var mode: TVConnectionMode
}

struct RememberedTV: Sendable, Identifiable, Hashable, Codable {
    var id: String { udn }
    let udn: String
    var friendlyName: String
    var modelName: String
    var lastIP: String
    var mac: String?            // filled in after the first REST probe
}

protocol TVService: Sendable {
    var state: TVConnectionState { get }
    func connect(to device: TVDevice) async throws
    func send(_ command: TVCommand) async throws
    func disconnect() async
    func forget(_ device: TVDevice) async  // wipes stored token for this TV
}

protocol TVTokenStore: Sendable {
    func token(for udn: String) async -> String?
    func save(_ token: String, for udn: String) async throws
    func delete(for udn: String) async throws
}

protocol RememberedTVsStore: Sendable {
    func all() async -> [RememberedTV]
    func upsert(_ tv: RememberedTV) async throws
    func delete(udn: String) async throws
}

protocol WakeOnLANService: Sendable {
    func wake(mac: String) async throws
}

struct DiscoveredTV: Sendable, Identifiable, Hashable {
    var id: String { udn }          // UPnP UDN — stable across reboots, unlike IP
    let ip: String
    let friendlyName: String
    let modelName: String
    let udn: String
}

protocol TVDiscoveryService: Sendable {
    func discoveries() -> AsyncStream<DiscoveredTV>
    func start() async
    func stop() async
}
```

`TVURLBuilder` produces the connect URL from `TVDevice` + Base64-encoded app name (`?name=…`) and appends `&token=<value>` when present. `SamsungTVService` builds a fresh `URLSession` per connect: for `.plain` it uses `.shared`; for `.secure` it constructs a session with `SamsungTrustDelegate`, which handles `URLAuthenticationChallenge` by accepting the server trust (via `URLCredential(trust:)`) — isolated so the trust bypass cannot leak into other traffic. A background `Task` reads frames and drives state transitions until `.connected`. View models are `@Observable @MainActor`, injected with `any TVService`. Switching mode = `disconnect()` then `connect(to:)` with a new `TVDevice`.

**Token lifecycle** — `SamsungTVService` is injected with a `TVTokenStore` and a `RememberedTVsStore`. Before connecting, it calls `tokenStore.token(for: device.udn)` and passes the result to `TVURLBuilder`. The frame reader parses the incoming `ms.channel.connect` event: when `data.token` is non-nil, it's persisted via `tokenStore.save(_:for:)`. If the TV rejects a stale token (auth error on the first frame), the service deletes it and retries the connect **once** without the token — this transparently triggers a fresh pairing popup rather than a silent failure. Immediately after `.connected` the service fires `SamsungDeviceInfoService` to capture the MAC and writes/updates a `RememberedTV` record. `forget(_:)` maps to both `tokenStore.delete(for:)` and `rememberedStore.delete(udn:)`.

**Keychain specifics** — `kSecClassGenericPassword`, `kSecAttrService = "com.remotetv.samsung.token"`, `kSecAttrAccount = device.udn` (stable; IP changes on DHCP renewal), `kSecAttrAccessible = kSecAttrAccessibleAfterFirstUnlock`. All calls wrapped in an `actor` so the sync `SecItem*` C APIs never block the main thread and their `Sendable`-unsafe flags stay contained.

**Discovery mechanics** — `BonjourDiscoveryService` is an `actor` backed by `NWBrowser` with an `NWBrowser.Descriptor.bonjourWithTXTRecord(type: "_samsungmsf._tcp", domain: nil)` descriptor. On `start()` it installs a `browseResultsChangedHandler` that receives the full result set on every change, dedupes by `"<name>.<type>.<domain>"`, and for each new result:

1. Pulls `u` / `fn` / `md` out of the Bonjour TXT record (`NWBrowser.Result.Metadata`) — falling back to the service name + `"Samsung TV"` when an older model omits a field.
2. Spins up a short-lived `NWConnection(to: result.endpoint, using: .tcp)` purely to resolve the service endpoint. On transition to `.ready`, it reads `currentPath?.remoteEndpoint` to pull out the dotted-quad IP, then cancels the connection.
3. Yields a `DiscoveredTV(ip:friendlyName:modelName:udn:)` onto the `AsyncStream` consumed by `DiscoveryViewModel`.

`stop()` cancels the browser and any in-flight resolver connections; the stream itself stays alive so a subsequent `start()` resumes emitting onto the same continuation.

**Entitlements** — Browsing Bonjour via `NWBrowser` uses the OS-managed mDNS responder and does **not** require the `com.apple.developer.networking.multicast` entitlement. The only platform requirements are `NSBonjourServices` (listing `_samsungmsf._tcp`) and `NSLocalNetworkUsageDescription` in `Info.plist`. WoL broadcast is covered by the same Local Network permission.

**Wake-on-LAN mechanics** — `MagicPacketBuilder` accepts a MAC in any common form (`AA:BB:CC:DD:EE:FF`, `AA-BB-…`, `AABBCC…`) and produces a 102-byte payload: 6 bytes of `0xFF` followed by the MAC repeated 16 times. `UDPBroadcastWakeService` opens an `NWConnection` to `NWEndpoint.hostPort(host: "255.255.255.255", port: 9)` over UDP and sends the packet as **3 bursts spaced 500ms apart** (handles stray packet loss). After firing, `DiscoveryViewModel` restarts the SSDP scan and waits up to ~15s for the TV to reappear; once it does, the app auto-connects using the stored token. If the MAC is unknown (first-run, or user cleared data), the "Wake" affordance is disabled with an explanatory caption.

**MAC acquisition** — `SamsungDeviceInfoService` performs a `GET http://<ip>:8001/api/v2/` immediately after the WebSocket transitions to `.connected`, decodes `device.wifiMac`, and writes it back via `RememberedTVsStore.upsert(_:)`. The probe is fire-and-forget — it never blocks commands. Missing MAC is non-fatal; it just means Power On isn't available for that TV until the next successful connect.

**TV-side requirement** — Samsung TVs must have "Network Standby" / "Power On with Mobile" enabled (Settings → General → Network → Expert Settings on most models). An in-app help sheet linked from `DiscoveryView`'s empty/off states explains this.

## UI

- `DiscoveryView`:
  - On appear, `DiscoveryViewModel.start()` — shows "Searching for TVs…" placeholder with a `ProgressView`
  - `List` merges **two sources** by `udn`:
    - **Live** — `AsyncStream<DiscoveredTV>` from `BonjourDiscoveryService`
    - **Remembered** — `RememberedTVsStore.all()` (TVs seen in prior sessions)
    - A TV present in both → status pill "Available"; remembered but missing from the live stream → "Off"
  - Each `TVListRow` shows `friendlyName`, `modelName`, `lastIP`, plus status pill
  - Global `Picker("Mode", selection: $mode)` with `.pickerStyle(.segmented)` at the top — "Plain (8001)" / "Secure (8002)"; value remembered in `@AppStorage`
  - **Available row** tap → builds `TVDevice(udn:ip:name:mode:)` and pushes to `RemoteView` via `navigationDestination(for:)`
  - **Off row** tap → `Button("Wake", systemImage: "power")` (disabled with caption if `mac` is nil); on tap: send magic packet, restart scan, auto-connect as soon as the TV reappears (~5–15s)
  - Toolbar **Refresh** button restarts the scan
  - After a ~10s timeout with no live results **and** no remembered TVs, an empty state appears: `ContentUnavailableView` ("No TVs found — check that the TV is powered on and on the same Wi-Fi") plus a **Try Again** button and a **"Power On not working?"** help link that opens a sheet explaining the TV-side Network Standby setting
  - No manual-IP text field — strictly discovery-only per the request
- `RemoteView`: grid of `RemoteButton`s using SF Symbols (`chevron.up/down/left/right`, `circle.fill`, `arrow.uturn.backward`, `house`, `speaker.wave.2`, `speaker.slash`, `power`). Status pill binds to `TVConnectionState`. A small "lock" / "lock.open" glyph in the pill reflects current `TVConnectionMode`. Buttons use `Button("Up", systemImage: "chevron.up", action: …)` per project conventions. Toolbar `Menu` contains: "Disconnect & switch mode" and "Forget this TV" (clears the stored token — next connect re-pairs with a fresh popup).

## Build order

1. Scaffold project + Domain types (incl. `TVConnectionMode`, `TVDevice` with UDN, `DiscoveredTV`, `RememberedTV`) + add `NSBonjourServices` + `NSLocalNetworkUsageDescription` to `Info.plist`
2. `TVCommandEncoder` + `TVURLBuilder` + `MagicPacketBuilder` + their tests (no device needed — fast feedback; exact byte-layout assertions for the 102-byte packet)
3. `TVTokenStore`/`KeychainTVTokenStore` (UDN-keyed) + `RememberedTVsStore`/`FileRememberedTVsStore` + round-trip tests
4. `SamsungDeviceInfoService` — REST probe with fake-URLProtocol tests
5. `BonjourDiscoveryService` using `NWBrowser` + real-network smoke test — your TV should appear in the list within ~3s
6. `UDPBroadcastWakeService` + real-network smoke test — with TV in standby, send magic packet and verify the TV powers on (user observes physically)
7. `SamsungTrustDelegate` + `SamsungTVService` connect/pair/disconnect + token save / load / retry-on-reject + post-connect MAC capture — exercised against both ports
8. `DiscoveryView` + VM (live+remembered merge, Wake action, mode picker, refresh, empty state with help link)
9. `RemoteView` + VM (toolbar menu: mode-switch + "Forget this TV")
10. End-to-end smoke test:
    a. Cold launch with TV on → appears as "Available" → tap → popup → pair → relaunch → silent reconnect
    b. Turn TV off → relaunch → row appears as "Off" with **Wake** → tap Wake → TV powers on within ~10s → auto-connects silently
    c. "Forget this TV" → token + remembered record wiped → next connect shows popup again
    d. Toggle mode picker (Plain ↔ Secure) and repeat (a)–(c)

Verify each step with `BuildProject`; `RenderPreview` on the two views.

## Decisions needed before coding

1. ~~**Port**~~ — resolved: both `ws://…:8001` and `wss://…:8002` supported with a segmented-control switch at the top of `DiscoveryView`. Cert trust for `wss` is bypassed via `SamsungTrustDelegate`; acknowledged not App Store safe and fine for POC.
2. ~~**Manual IP**~~ — resolved: removed. Discovery-only via Bonjour/mDNS.
3. ~~**Discovery approach**~~ — resolved: first SSDP/UPnP attempt didn't produce results on the target network; swapped to `NWBrowser` over `_samsungmsf._tcp`. Drops the multicast entitlement entirely.
4. **Info.plist `NSLocalNetworkUsageDescription`** — revised to mention discovery: `"RemoteTV uses local network access to find and control your Samsung TV."` OK?
5. **ATS exception for `.secure`**: since the TV uses a self-signed cert on `wss:8002`, add `NSAppTransportSecurity` → `NSAllowsArbitraryLoads` (or a narrower `NSExceptionDomains` entry keyed on the TV IP, if desired). OK with arbitrary-loads for POC, or prefer scoping?
6. **Pairing UX**: first connect shows a popup on the TV; user accepts with the physical remote once. The returned token is persisted in Keychain keyed by **UDN** (stable across DHCP renewal), so subsequent launches reconnect silently. "Forget this TV" in the toolbar wipes the token and the remembered record, forcing a re-pair. (Confirm Keychain for token + JSON file for non-secret metadata.)
7. **WoL broadcast address**: proposing limited broadcast `255.255.255.255:9`. Alternative: resolve the current Wi-Fi subnet-directed broadcast (e.g. `192.168.1.255`), slightly more robust on unusual home networks. OK with limited broadcast for POC?
8. **WoL packet count**: proposing 3 bursts, 500ms apart. Some apps send 5. Preference?
9. **Target**: iPhone-only for POC.

## Phase 2 backlog

- Subnet-directed WoL (resolve the current Wi-Fi subnet broadcast instead of `255.255.255.255`) for routed/odd home networks
- App launch (`ms.channel.emit` → `ed.apps.launch`) — YouTube, Netflix, etc.
- Proper cert pinning for `.secure` (replace blanket trust with TV-specific `SecTrust` evaluation) — needed for App Store submission
- iCloud Keychain sync of tokens so the same remote on iPad/Mac pairs silently
- Multi-TV support: list of remembered TVs with per-TV tokens, "last used" default
- Reconnection with exponential backoff + keep-alive pings
- iPad layout, landscape
- REST device-info probe (`http://<ip>:8001/api/v2/`) to show TV name/model pre-connect
