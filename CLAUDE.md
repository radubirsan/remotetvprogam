# RemoteTV

iOS app that acts as a remote control for Samsung Tizen smart TVs. Finds TVs on the local
network, opens a WebSocket control channel, and sends key-code commands.

> Swift/SwiftUI style rules live in `/Users/radu/Desktop/CLAUDE.md` (parent dir). Don't
> duplicate them here — this file is only the project-specific map.

## Stack

- **iOS 26+, Swift 6.2+, strict concurrency.** Targeting iOS 26 is intentional — do not
  down-target.
- **SwiftUI only.** No UIKit unless requested.
- **No third-party frameworks.** Everything is Foundation + Network.framework + SwiftUI.
- Tests use **Swift Testing** (`@Test`, `#expect`), not XCTest.
- **`TVScheduel/` is a separate SwiftPM package** (the EPG grabber), not part of the Xcode
  project. It targets `swift-tools-version 5.9` / macOS 13 and is deliberately written to
  also build under Linux Swift (for CI) — so it can NOT use the iOS-26-only APIs the app
  freely uses. See its own section below.

## Project layout

```
RemoteTV/
  App/              RemoteTVApp.swift — composition root, builds concrete services.
                    RootView.swift   — switches Discovery ⇄ Remote on @AppStorage state.
  Domain/           Value types (DiscoveredTV, RememberedTV, TVDevice, TVCommand,
                    TVConnectionMode, TVConnectionState, TVPowerState, TVServiceError,
                    TVApp, InstalledApp, KnownTVApps, SniffLogEntry).
                    EPG types: EPGGuide, EPGChannel, EPGProgramme, KnownChannelNumbers.
  Discovery/        TVDiscoveryService protocol + BonjourDiscoveryService (NWBrowser +
                    direct subnet scan).
  Services/         Everything network/persistence:
                      SamsungTVService       — WebSocket transport + pairing + heartbeat
                      SamsungTVService+Voice — Bixby voice-session extension (see Bixby.md)
                      YouTubeLoungeClient    — YouTube Lounge cast client (see YTCAST.md)
                      SamsungTrustDelegate   — accepts TV self-signed certs on :8002
                      SamsungDeviceInfoService — reads /api/v2/ to grab MAC
                      TVURLBuilder           — builds ws/wss URLs (includes token)
                      TVCommandEncoder       — JSON body for a key press
                      KeychainTVTokenStore   — pairing tokens in Keychain
                      FileRememberedTVsStore — remembered-TV JSON in Application Support
                      UDPBroadcastWakeService + MagicPacketBuilder — WoL
                      MicrophoneCaptureService — 16 kHz mono PCM chunks for Bixby voice
                      NetworkMonitor         — NWPathMonitor → "is the phone on Wi-Fi/LAN?"
                      EPGClient              — actor that fetches/caches the EPG JSON dump
  Features/
    Discovery/      DiscoveryView + DiscoveryViewModel + TVListRow.
    Remote/         RemoteView + RemoteViewModel; RemoteSamsungBody is the redesigned
                    canvas, composed from the design atoms (RemoteTheme, CircleButton,
                    Rocker, DPad, AppSlot) in RemoteSamsungStyle.swift. Per-section button
                    groups (DPadSection, VolumeSection, ChannelSection,
                    BottomActionsSection, TrackpadSection, NumberPadView,
                    CommercialMuteSection, …) + side panels (SidePanelMode +
                    RemoteSidePanel{EPG,Shortcuts,InstalledApps,SniffLog}). EPGViewModel
                    drives the EPG panel; NowOnTVPill shows the pinned channel's show.
                    MediaCastView = photo/video/YouTube casting screen;
                    KeyboardInputView = typed-text input over SendInputString.
    Onboarding/     First-run wizard: OnboardingView (host + progress dots) +
                    OnboardingViewModel + one Onboarding*Step.swift file per step,
                    sharing OnboardingStepScaffold.
  Resources/        Info.plist, RemoteTV.entitlements, Localizable.xcstrings, Assets.xcassets.
RemoteTVTests/      Swift Testing target — one file per SUT.
TVScheduel/         Standalone SwiftPM package: Romanian XMLTV → JSON grabber (see below).
.github/workflows/  epg-update.yml — daily CI that publishes guide.json to `epg-data` branch.
PLAN.md             Long-form design doc; useful for "why" but can drift from code.
Bixby.md            Wire protocol notes for the Bixby voice streaming path.
YTCAST.md           Wire protocol notes for the YouTube DIAL + Lounge cast path.
SmartThingsAPI.md   Notes on the cloud API (not used by the app; reference only).
TODO.md / HANDOFF.md  Scratch planning docs; can drift — this file is the live map.
```

View models are `@MainActor @Observable` and owned via `@State`. Services are injected via
init so tests swap in fakes.

`RootView` is the real top of the tree (not `DiscoveryView`): it renders `RemoteView` when
`@AppStorage("lastRemoteDeviceJSON")` holds an encoded `TVDevice`, otherwise `DiscoveryView`.
Discovery writes that key when a TV is picked; Remote clears it on disconnect/forget. The
`.id(device.id)` on `RemoteView` is load-bearing — it forces a fresh instance (and a fresh
`.task` → `connect()`) when the user switches TVs. Don't remove it.

## Key flows

### Discovery

Bonjour/mDNS via `NWBrowser` browsing `_samsungmsf._tcp`. The TXT record carries `u` (UDN),
`fn` (friendly name), `md` (model). Each browse result is resolved through a short-lived
`NWConnection` pinned to IPv4 (Samsung's remote APIs won't accept an IPv6 link-local
literal as a WebSocket host). The resolved IP is passed up as a `DiscoveredTV`.

Two reliability layers sit on top of the browser (added for the fresh-install and
multi-TV cases):
- A **proactive re-query** at +3s/+7s — `NWBrowser` drops its in-flight PTR query while
  the Local Network prompt is up and never re-broadcasts after the user taps Allow.
  Deliberately gentle (and stops once results arrive): *restarting* the browser tears
  down the live listener and misses late unsolicited announcements.
- A **direct subnet scan** that probes the local /24 for port 8001, so a second TV that
  doesn't answer mDNS still surfaces. Both paths dedupe by IP before yielding.

`DiscoveryViewModel` merges live stream results with `RememberedTV` records on disk:
matched by UDN first, then by IP. Live → `.available`, remembered-but-missing → `.off`
(Wake button if MAC is known).

- Search is **manual**: the view calls `viewModel.loadRemembered()` on appear; the toolbar
  has a Search/Stop toggle that calls `start()` / `stop()`.
- After ~10s of scanning with zero live + zero remembered, `showEmptyState` flips true and
  `EmptyStateView` replaces the list (with Retry / Help / Back buttons).
- **Tapping a discovered row copies its IP into the "Connect by IP" field**, it does not
  navigate. The Connect arrow on that field pushes the `RemoteView`. (Yes, this was a
  deliberate UX choice — users wanted to confirm the IP before connecting.)

### Connect / pairing

`SamsungTVService.connect(to:)`:
1. Builds a ws/wss URL via `TVURLBuilder`, including a stored Keychain token if present.
2. On `wss://`, `SamsungTrustDelegate` accepts the TV's self-signed cert.
3. If the TV rejects the stored token, the service deletes it and retries once — the TV
   displays its pairing popup, the user accepts with the physical remote, and the new
   token is persisted.
4. First successful connect also runs `SamsungDeviceInfoService` to fetch the TV's MAC
   and upsert a `RememberedTV` record so Wake-on-LAN works later.

`RemoteViewModel.connect()` is called from `RemoteView.task`. Do not move the `connect()`
call out of `.task` without understanding why it's there — the previous bug where power
and DPad did nothing was *exactly* that connect never ran.

Token persistence is **dual-keyed** (IP + MAC): the IP-keyed Keychain slot is checked
first, and a miss falls back to the MAC slot — this is what stops a DHCP lease rotation
from re-prompting the pairing popup. The info-poll back-fills the MAC slot if the MAC
wasn't known at handshake time. Connects also retry up to 4× on *transient* network
errors (`SamsungTVService.isTransientNetworkError`) because at cold launch the socket
can fire before iOS brings the local-network path up.

### Heartbeat & reconnect

While connected, `SamsungTVService` pings the socket every 15s (`startHeartbeat`) —
Samsung TVs/NATs silently drop idle sockets without a close frame, so without this the
first key press after a long idle failed. Two subtleties are load-bearing:
- **A missing pong is NOT a dead socket.** Many Samsung TVs simply never answer pings,
  so the heartbeat reconnects only on a definite transport *error* (`PingOutcome.failed`),
  never on `noAnswer` — conflating them churned the connection every 15s.
- The reconnect runs in a detached `Task` on purpose: `connect()` → `teardown()` cancels
  the heartbeat task itself, so reconnecting inline would cancel its own `connect`.

The heartbeat also skips while `voiceSessionActive` so a keepalive can't tear Bixby down
mid-utterance. Separately, `reconnectIfNeeded()` (scene-phase hook) re-handshakes on
foregrounding when iOS killed the socket while suspended.

### Bixby voice (hold-to-talk)

`SamsungTVService+Voice.swift` + `MicrophoneCaptureService`; protocol notes in `Bixby.md`.
Flow: send `KEY_BT_VOICE` **Press and keep it held** (an immediate Release closes Bixby on
this firmware), wait for the TV's `ms.voiceApp.recording` event, stream 16 kHz mono PCM
chunks as binary frames, then send an empty end-of-stream marker + the Release.
`RemoteViewModel.startVoice()` warms the mic engine *before* opening Bixby so audio can
start the instant the TV is ready.

### YouTube casting (Lounge)

`castYouTubeVideo` opens a specific video in the TV's YouTube app the way Chromecast
does; notes in `YTCAST.md`. Three steps: (1) foreground YouTube via the plain REST
app-launch — **not** a DIAL launch, which pops Multi View when another source is active;
(2) scrape the `screenId` from the DIAL state document (GET only, polled, no Origin
header); (3) drive playback via `YouTubeLoungeClient` (token → bind → setPlaylist). The
Lounge API is undocumented Google internals and can break without notice — every stage
logs to the sniff log so failures point at the broken step.

### Onboarding

`Features/Onboarding/` is a first-run wizard (welcome → Wi-Fi check → find TV → pair →
success → test → optimize), also replayable from the gear menu (`isReplay`). It reuses
the real services; the pair step just awaits `service.connect`. Pairing defaults to
`.secure` (wss:8002) since that's every 2019+ model. `RootView` decides when to show it
and receives the paired `TVDevice` via `onFinished`. `NetworkMonitor` also drives a
"join the TV's Wi-Fi" overlay in `RootView` whenever the phone has no Wi-Fi/wired path.

### App launching & installed app detection

Launching apps goes over HTTP, not the WebSocket: `POST http://<ip>:8001/api/v2/applications/<appID>`.
The WebSocket path (`ms.channel.emit` + `ed.apps.launch`) silently no-ops on recent Tizen
builds — don't bring it back. `TVService.launch(appID:)` takes a raw ID so both hard-coded
shortcuts (`TVApp`) and dynamically detected apps (`InstalledApp`) share one code path.

**Installed Apps** (`InstalledAppsSection` → `requestInstalledApps`) probes numeric Tizen
IDs in `KnownTVApps.catalog` via `GET /api/v2/applications/<id>`, parallelized with
`withTaskGroup`. Returns *only* matches (filtered list). Buttons are named from the TV's
response body so rebranded apps show their current name. Entries deduped by lowercased
name so the HBO Go / HBO Max / Max variant probes collapse into one button. Adding a new
app is a one-line append to the catalog.

We originally tried `ed.installedApp.get` over the WebSocket — it'd return the whole list
in one round-trip — but recent Tizen firmware silently ignores the frame on every TV we've
tested. Don't bring it back.

We also briefly had a parallel **DIAL Apps** section (port 8080 `/ws/apps/<Name>`) that
probed the standard DIAL registry. It was removed because modern Samsung TVs only register
Netflix + YouTube with DIAL — everything else is silent even when installed, so the list
was uselessly sparse. The numeric-ID probe subsumes all practical cases. Don't reintroduce
DIAL without a concrete reason; it's a dead end on this platform.

### WebSocket sniffer

`SamsungTVService` keeps a rolling 300-entry buffer of control-channel traffic
(inbound frames, outbound sends, connect/disconnect info). It's exposed as
`TVService.sniffLog` and rendered by `SniffLogSection` under the bottom action row.
Primary use is harvesting Tizen app IDs: launch an app on the TV with the physical remote
and watch for emitted frames. Keep it in — it's the fastest path to fixing a stale catalog
entry next time Samsung rebrands something.

### Wake-on-LAN

`UDPBroadcastWakeService` sends a magic packet (`MagicPacketBuilder`) to `255.255.255.255`
UDP port 9. Requires a MAC on file (captured on first successful connect). After sending,
the Discovery VM reruns `start()` so the woken TV surfaces as `.available`.

### Power state vs connection state

`TVPowerState` (`unknown`/`on`/`off`) is a *separate axis* from `TVConnectionState`. The
WebSocket can stay connected while the TV is in standby, so the UI tracks both — e.g. the
status LED is dim grey for "connected but standby" vs solid green for fully active. Power
state is derived from `device.PowerState` on the `GET /api/v2/` REST poll. The Power button
toggles standby; surfacing standby is what the "Sandby / Power button" work added.

### TV Guide / EPG

This is a **read-only** electronic programme guide, entirely decoupled from TV control —
nothing here goes over the WebSocket. The data path is:

1. **`TVScheduel/` package** (see its section) runs as a daily GitHub Action
   (`.github/workflows/epg-update.yml`), fetches a Romanian XMLTV feed, and force-pushes
   `guide.json` to an orphan `epg-data` branch.
2. **`EPGClient`** (an `actor` in `Services/`) downloads that JSON from GitHub raw
   (`EPGClient.Configuration.defaultSourceURL`), with an in-memory + on-disk cache (24h TTL,
   `URL.cachesDirectory/epg`). Decodes into `EPGGuide` (`channels` + `programmes` +
   `fetchedAt`).
3. **`EPGViewModel`** drives `RemoteSidePanelEPG`: channel list with search, drill-in to a
   channel's schedule, "now playing" per row, and a *pinned* channel (persisted in
   `UserDefaults` key `pinnedTVChannelID`) that feeds `NowOnTVPill` above the remote.

**Why the pin is manual, not auto-detected:** Tizen's WebSocket is silent on channel changes
and there's no documented REST endpoint for the current broadcast channel (only SmartThings
cloud OAuth exposes it). A manual pin is the honest option until a sniff-log frame proves
otherwise — don't claim auto-detection.

**Tune macro:** `KnownChannelNumbers` maps EPG channel ids (`Digi.24.HD.ro` style) → TV
channel numbers for a specific Digi cable lineup. `EPGViewModel.tuneCommands` turns a number
into per-digit `TVCommand`s + a trailing `KEY_ENTER` (the Enter avoids Tizen's ~1.5s
post-digit tune delay). Channels not in the table simply have no Tune button — the lineup
varies by region/tier, so the map is a sensible default, not ground truth.

## Conventions

- **Service protocols sit in their own files** (`TVService.swift`, `TVDiscoveryService.swift`,
  `RememberedTVsStore.swift`, `WakeOnLANService.swift`, `TVTokenStore.swift`); concrete
  impls live alongside them.
- `@Observable` VMs are **always** `@MainActor` (project has no main-actor default).
- Pure helpers (the row-merge in `DiscoveryViewModel.makeRows`, `TVCommandEncoder`,
  `TVURLBuilder`, `MagicPacketBuilder`) are `static` and have direct unit tests.
- Dedupe key inside `DiscoveryViewModel` is **IP, not UDN** — some Samsung TVs omit `u`
  from the TXT record, and using UDN caused duplicate rows.
- `@AppStorage("lastConnectionMode")` persists plain/secure. Don't change the key.
- **Error surfacing**: view models set their error string from `error.displayMessage`
  (extension on `Error` in `TVServiceError.swift` — curated `TVServiceError` copy when
  it is one, `localizedDescription` otherwise). `RemoteViewModel` funnels service calls
  through its `perform(_:)` helper; don't reintroduce per-call-site catch pairs.
- `SamsungTVService` is split across files: voice methods live in the
  `SamsungTVService+Voice.swift` extension, so the stored voice state and the few
  members it needs (`webSocketTask`, `transmit`, `appendSniff`, `messageData`) are
  internal rather than private. Keep new members private unless an extension file
  genuinely needs them.

## Xcode project file — adding new Swift files

`RemoteTV.xcodeproj/project.pbxproj` uses deterministic UUIDs (`A2…F0XX` for file refs,
`B2…F0XX` for Sources build files). To add a new source file, insert four entries:

1. `PBXBuildFile` section — `B2000000000000000000F0xx /* Foo.swift in Sources */`
2. `PBXFileReference` section — `A2000000000000000000F0xx /* Foo.swift */`
3. The file's containing `PBXGroup` (e.g., the `Remote` group) — add `A2…F0xx`
4. The app target's `PBXSourcesBuildPhase` — add `B2…F0xx`

Grep for an existing sibling file (e.g. `VolumeSection`) to copy the pattern. Test files
use `D2…F0XX` build-file UUIDs and go in the test target's group + Sources phase instead.
Currently the highest used suffix is `F071`. Suffixes `F040`–`F042` are retired (they
belonged to the removed DIAL feature); don't reuse them. (`RemoteSamsungStyle.swift` is
the one exception to the deterministic-UUID scheme — it kept its Xcode-generated UUID
when it was moved into `Features/Remote/`.)

`TVScheduel/` files do NOT go in the pbxproj — that package builds with SwiftPM, not Xcode.

## Gotchas — things that have been tried and rejected

- **SSDP / UPnP discovery**: doesn't work reliably on consumer networks and forced the
  `com.apple.developer.networking.multicast` entitlement. Ripped out; replaced with
  Bonjour. Do not reintroduce.
- **Multicast entitlement**: not needed. `RemoteTV.entitlements` should stay empty unless
  a compelling new reason arrives.
- **IPv6 from Bonjour resolution**: Samsung's control port rejects IPv6 link-local
  hosts. `BonjourDiscoveryService.resolve` forces `NWProtocolIP.Options.version = .v4`.
  Zone identifiers (`%en0`) are also stripped in `extractIP`.
- **`NWBrowser` permission prompt**: On a fresh install, the browser can run silently
  without iOS ever prompting for Local Network access. `start()` fires a throwaway UDP
  connection to `224.0.0.251:5353` (`primeLocalNetworkPermission`) to force the prompt
  up front. Don't remove this.
- **Auto-starting the scan on view appear**: intentionally removed. The user must tap
  Search. Load-on-appear now only populates remembered TVs.
- **`device(for:)` on DiscoveryViewModel**: kept for now but unused by the view — tapping
  a row populates `manualIP` instead of navigating. Safe to prune alongside its tests if
  you're sure you won't need it.

## TVScheduel package (EPG grabber)

Standalone SwiftPM package under `TVScheduel/`. Produces a `tvepg` CLI and a `TVScheduel`
library; the iOS app does **not** link the library — it consumes the *output* JSON via
`EPGClient` instead. Pieces: `XMLTVFetcher` (download + 24h disk cache + gzip),
`XMLTVParser` (`<channel>`/`<programme>` → `Guide`), `XMLTVDate` (XMLTV timestamp parsing),
`Models` (`Channel`, `Programme`, `Guide` — `Sendable`/`Codable`).

**Cross-platform constraint:** this package must build on **both** Apple SDKs and **Linux
Swift**, because CI used to run it on Ubuntu. Consequences baked into the code, keep them:
- `@preconcurrency import Foundation` + `#if canImport(FoundationNetworking)` for URLSession.
- `performRequest` bridges `dataTask(_:completionHandler:)` to async via a continuation —
  Linux's `FoundationNetworking` lacks the native `URLSession.data(for:)`.
- gzip via Apple's `Compression` is `#if canImport(Compression)`-gated; on Linux it throws,
  so callers must pre-decompress (the CI does `curl … | gunzip | tvepg dump --input -`).
- Avoid iOS-26/macOS-only Foundation conveniences in this package even though the app uses
  them freely. (The `epg-update.yml` workflow now runs on `macos-latest` anyway, but the
  Linux-safety in the code is intentional — don't rip it out.)

```sh
cd TVScheduel
swift run tvepg channels            # list channels
swift run tvepg today "Digi 24"     # today's schedule for a channel
swift run tvepg dump > guide.json   # full guide as JSON (what CI publishes)
swift test                          # XMLTVParser + XMLTVDate tests
```

## EPG CI pipeline

`.github/workflows/epg-update.yml` runs daily (04:00 UTC) + on push to the workflow/package:
builds the CLI, fetches the epgshare01 RO feed, and force-pushes `guide.json` to the orphan
`epg-data` branch (rewritten each run so 15 MB blobs don't accumulate in `main`'s history).
`EPGClient.Configuration.defaultSourceURL` points at that branch's raw URL — if the repo
owner/name changes, update that constant.

## Info.plist requirements

- `NSBonjourServices` must contain `_samsungmsf._tcp`.
- `NSLocalNetworkUsageDescription` must be a human-readable string — it's shown in the
  permission prompt.
- `NSAppTransportSecurity.NSAllowsArbitraryLoads = true` so the WebSocket can open against
  a plain `ws://` TV without ATS blocking it.

## Running

Open `RemoteTV.xcodeproj` in Xcode and run on a physical device (or a simulator that's on
the same Wi-Fi — discovery won't find TVs from a Mac-only simulator network).

Prefer the Xcode MCP tools over shelling out:
- `BuildProject` after non-trivial changes.
- `GetBuildLog` / `XcodeListNavigatorIssues` for diagnostics.
- `RenderPreview` to sanity-check SwiftUI changes.
- `XcodeRead` / `XcodeWrite` / `XcodeUpdate` when touching Xcode project files.

## Tests

App (Swift Testing, runs on a simulator — pick any installed iPhone simulator):

```
xcodebuild test -project RemoteTV.xcodeproj -scheme RemoteTV -destination 'platform=iOS Simulator,name=iPhone 17'
```

EPG package (SwiftPM, no simulator needed):

```
cd TVScheduel && swift test
```

Unit-tested surfaces: `TVCommandEncoder`, `TVURLBuilder`, `KeychainTVTokenStore`,
`FileRememberedTVsStore`, `MagicPacketBuilder`, `RemoteViewModel`, `DiscoveryViewModel`
(including the pure `makeRows` merge logic), `TrackpadGestureMapper`, `EPGViewModel`
(tune macro + channel filtering), `EPGClient` (cache layering via `file://` sources),
`OnboardingViewModel` (select → pair flow), `SamsungTVService.isTransientNetworkError` +
`firstRegexMatch`; and in `TVScheduel/`: `XMLTVParser`, `XMLTVDate`.

Still untested (needs heavier mocks): the heartbeat ping classification, the voice
continuation lifecycle, `BonjourDiscoveryService`, `MicrophoneCaptureService`, and the
live `YouTubeLoungeClient` HTTP flow.
