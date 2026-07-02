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
- **`RemoteTVCore/` is a local Swift package = the shared "engine"** (TV-control domain
  types + the whole networking/persistence stack + `TVIntentsController` + `SharedStorage`).
  The app, the `RemoteTVExtension` widget extension, and the test target all link it, so the
  engine has one source of truth and the Control Center controls can drive the real
  `SamsungTVService`. Pure Foundation/Security/Darwin/Observation — no SwiftUI/UIKit and no
  AppIntents *conformances* (intent/entity types stay per-target). See "Shared engine package".
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
  Domain/           App/UI-only value types: DiscoveredTV + the EPG types (EPGGuide,
                    EPGChannel, EPGProgramme, KnownChannelNumbers). The TV-control value
                    types (TVDevice, TVCommand, TVConnection*, TVPowerState, TVServiceError,
                    RememberedTV, TVApp, InstalledApp, KnownTVApps, SniffLogEntry) moved to
                    the RemoteTVCore package.
  Discovery/        TVDiscoveryService protocol + BonjourDiscoveryService (NWBrowser +
                    direct subnet scan).
  Services/         App-only services: EPGClient (EPG JSON fetch/cache), NetworkMonitor
                    (Wi-Fi/LAN path), MicrophoneCaptureService (Bixby mic). The networking/
                    persistence ENGINE — SamsungTVService [+Voice], YouTubeLoungeClient, the
                    stores, UDPBroadcastWakeService/MagicPacketBuilder, TVURLBuilder,
                    TVCommandEncoder, SamsungTrustDelegate, SamsungDeviceInfoService — moved
                    to the RemoteTVCore package.
  Intents/          App-side App Intents (Siri / Shortcuts / Spotlight / Action button):
                      TVControlIntents       — power, mute, volume, open app, tune intents
                      TVChannelEntity / TVAppEntity — static entity catalogs
                      RemoteTVAppShortcuts   — zero-setup Siri phrases
                    (TVIntentsController + SharedStorage — the shared backend — live in
                    RemoteTVCore so the widget extension can reuse them.)
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
RemoteTVCore/       Local Swift package — the shared engine (Domain control types + Services
                    networking/persistence + TVIntentsController + SharedStorage). Linked by
                    the app, the RemoteTVExtension widget extension, and the test target.
RemoteTVExtension/  Widget-extension target (Xcode synchronized folder). Control Center / Lock
                    Screen controls (TV Power, Mute) built on RemoteTVCore.
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

### App Intents (Siri / Shortcuts)

`RemoteTV/Intents/` exposes six intents: Toggle TV Power, Mute, Adjust Volume (direction
+ steps), Open App on TV, Change Channel (up/down), and Tune to Channel. All run
**in-process, in the background**
(no app open): iOS launches the app, `RemoteTVApp.init` registers `TVIntentsController`
with `AppDependencyManager`, and intents resolve it via `@Dependency`. Registration MUST
stay in `init` — `@Dependency` traps if unregistered, and background intent launches run
`init` but no scene.

The controller wraps the **same `SamsungTVService` instance the UI uses**, so an intent
fired while the app is open reuses the live socket. Cold launches read the last device
from the `lastRemoteDeviceJSON` UserDefaults slot (same key as `RootView`'s
`@AppStorage`) and connect with the shared Keychain token. Power mirrors the UI's
wake-mode logic: `KEY_POWER` when reachable, Wake-on-LAN magic packet when not (or when
the TV reports standby). Macros pace keys at the same 120 ms the UI uses
(`TVIntentsController.interKeyDelay` ↔ `RemoteView.tuneInterKeyDelay` — keep in sync).

Intents resolve their backend through `TVIntentsController.resolve()`, NOT `@Dependency`:
the app sets `TVIntentsController.shared` in `init` (live service, reused by in-app/Siri
intents), and `resolve()` returns that when present or builds a standalone stack from
shared storage otherwise. This is what lets the SAME intents run in the Control Center
widget extension's process, where `AppDependencyManager` is never populated and
`@Dependency` would trap. Don't reintroduce `@Dependency` here.

Entity catalogs are static on purpose (channels from `KnownChannelNumbers`, apps from
`TVApp` + `KnownTVApps` deduped): resolution must work with the TV off and without
network. `RemoteTVAppShortcuts` phrase rules, learned the hard way:
- Nothing that matches Siri's built-in home-control vocabulary ("turn on/off the TV") —
  it routes to HomeKit before app phrases and prompts HomeKit setup.
- App-name-first forms ("<app> power") are the most reliable. The display name is **Zapy**
  (`CFBundleDisplayName`), and `INAlternativeAppNames` re-registers "Zapy" with a
  pronunciation hint ("zap-ee") so Siri maps the spoken brand reliably. (Was "RemoteTV" +
  a "Cobalt" alias; "RemoteTV" transcribed as ordinary TV vocabulary.)
- Parameter values must be IN the phrase as `\(\.$param)` — two static phrases
  ("channel up"/"channel down") would both run the intent with its default.
- Entity-backed phrase parameters need the `updateAppShortcutParameters()` call in
  `RemoteTVApp.init`; vocabulary re-indexes on app (re)install.

### Shared engine package (`RemoteTVCore`)

The networking/persistence engine lives in a local Swift package so the app AND the widget
extension share one copy:
- **Contents:** the TV-control Domain value types, the whole Services stack (`SamsungTVService`
  [+Voice], `YouTubeLoungeClient`, the stores, WoL, URL/command builders, trust delegate,
  device-info), plus `TVIntentsController` and `SharedStorage`.
- **NOT in the package:** SwiftUI/UIKit, the Features/UI layer, Discovery, EPG, NetworkMonitor,
  MicrophoneCaptureService, and — deliberately — every `AppIntent`/`AppEntity`/`ControlWidget`
  *conformance*. Intent types stay per-target (app's Siri intents in `RemoteTV/Intents/`, the
  extension's control intents in `RemoteTVExtension/`) so each target's AppIntents metadata is
  generated from its own types — no cross-module duplicate-registration surprises.
- **Linkage:** linked by the app, the extension, and the test target. Xcode builds it as one
  shared framework (auto-dynamic, since two targets in the app consume it), so the engine is
  embedded once and shared — not duplicated per binary.
- **Public surface:** everything the app/extension call is `public` (value types have explicit
  `public init`s; `@Observable` props are `public private(set)`). Internal-only helpers
  (`SamsungTVService.isTransientNetworkError`, the free `firstRegexMatch`) stay internal —
  tests reach them via `@testable import RemoteTVCore`.
- **Adding engine files:** SwiftPM auto-discovers everything under
  `RemoteTVCore/Sources/RemoteTVCore/` — just drop the `.swift` in (Domain/Services/Intents
  subfolders), no pbxproj edit. Mark the API `public`. (App/extension UI files still follow
  the pbxproj / synchronized-folder rules below.)

### Control Center / Lock Screen controls

`RemoteTVExtension/` is the **widget-extension target** (controls can't be vended from an app
target; it's an Xcode file-system synchronized folder). It links `RemoteTVCore` and vends seven
`ControlWidget`s — **TV Power**, **Mute**, **Volume Up/Down**, **Channel Up/Down**, and
**Open RemoteTV** — whose intents call `TVIntentsController.resolve()` on the real engine.
Channel taps send a single key; Volume Up sends **2** `.volumeUp` and Volume Down sends **3**
`.volumeDown` per press (via the paced `send(macro:)`). **Open RemoteTV** foregrounds the app
via `OpenRemoteTVAppIntent` (`openAppWhenRun = true`, returns `.result()`). That intent lives in
`RemoteTV/Intents/OpenRemoteTVAppIntent.swift` with **dual target membership (app + extension)**
— load-bearing: the control references it (extension), and the system runs it in the APP
process to open the app. An extension-only intent does NOT open the app, and `OpenURLIntent`
to a custom scheme is unreliable on iOS 18. It can't go in `RemoteTVCore` either — SwiftPM
skips AppIntents metadata extraction, so package-defined intents never register. The dual
membership is the only working option; in the pbxproj it's two PBXBuildFiles (`B2…F07A` app,
`B3…F07A` ext) pointing at one fileRef (`A2…F07A`), one in each target's Sources phase. In the extension process `shared` is nil, so `resolve()` returns
`makeStandalone()`, which builds a fresh `SamsungTVService` from shared storage. Power toggles
`KEY_POWER` when reachable and falls back to Wake-on-LAN when the TV is off; Mute opens a fresh
socket and sends `KEY_MUTE`.

Cross-process state still rides on the same two capabilities (must be enabled on BOTH targets
in Xcode Signing & Capabilities):
- **App Group** (`group.com.remotetv.RemoteTV`): the app mirror-writes `lastRemoteDeviceJSON`
  (`RootView` → `SharedStorage`); the extension reads it to know which TV to target (and its
  MAC for WoL). Until enabled, controls degrade to a "no TV configured" dialog (no crash).
- **Pairing token** for **Mute** (it opens a socket, which needs the token): shared via the
  App Group, NOT Keychain Sharing. The app's token store is
  `MirroringTokenStore(primary: KeychainTVTokenStore(), mirror: AppGroupTokenStore())` — Keychain
  stays authoritative but every token is mirrored into the App Group; the extension's
  `makeStandalone()` reads it via `AppGroupTokenStore`. So only the **App Group** capability is
  needed (no Keychain Sharing). After enabling it, **connect from the app once** so the token
  mirrors; until then Mute re-triggers the TV's pairing popup. (Power-via-WoL needs only the MAC,
  so it never needed the token. `SharedStorage.keychainAccessGroup` is now unused.)

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

**First decide which target the file belongs to:**
- **Engine** (domain types, networking, persistence, the intents backend) → drop it under
  `RemoteTVCore/Sources/RemoteTVCore/` and mark its API `public`. SwiftPM auto-discovers it —
  **no pbxproj edit.**
- **Widget-extension** file → put it in `RemoteTVExtension/` (Xcode synchronized folder —
  auto-included, no pbxproj edit) and link against `RemoteTVCore`.
- **App UI / Features / app-side intents** → the app target uses explicit pbxproj membership
  (below).

For an **app-target** file: `project.pbxproj` uses deterministic UUIDs (`A2…F0XX` for file
refs, `B2…F0XX` for Sources build files). Insert four entries:

1. `PBXBuildFile` section — `B2000000000000000000F0xx /* Foo.swift in Sources */`
2. `PBXFileReference` section — `A2000000000000000000F0xx /* Foo.swift */`
3. The file's containing `PBXGroup` (e.g., the `Remote` group) — add `A2…F0xx`
4. The app target's `PBXSourcesBuildPhase` — add `B2…F0xx`

Grep for an existing sibling file (e.g. `VolumeSection`) to copy the pattern. Test files
use `D2…F0XX` build-file UUIDs and go in the test target's group + Sources phase instead.
Currently the highest used suffix is `F07A` (`OpenRemoteTVAppIntent.swift`, which is a member
of BOTH the app and extension targets — app build file `B2…F07A`, extension build file
`B3…F07A`, both referencing fileRef `A2…F07A`; the `B3…` prefix is the convention for an
app-source file also compiled into the extension). Suffixes `F040`–`F042` (removed DIAL feature)
and `F072`/`F079` (`TVIntentsController`/`SharedStorage`, which moved to `RemoteTVCore`) are
retired; don't reuse them. (`RemoteSamsungStyle.swift` is the one exception to the
deterministic-UUID scheme — it kept its Xcode-generated UUID when moved into
`Features/Remote/`.) The local-package wiring uses `AA…`/`AB…`/`AC…` UUIDs
(`XCLocalSwiftPackageReference` / `XCSwiftPackageProductDependency` / the `… in Frameworks`
build files on the app, extension, and test targets).

Neither `RemoteTVCore/` nor `TVScheduel/` files go in the pbxproj — both build with SwiftPM.

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

## Channel-number lineups (replacing hardcoded `KnownChannelNumbers`)

A channel **number** is a `(provider, zone, channel)` property — `Digi.24.HD.ro` is 59 on one
Digi county, different on another, different on Orange — so it can't live as a single field in
the daily-rewritten `guide.json`. Instead it's a **separate `lineups.json`** (schema v2):
`{schemaVersion:2, generatedAt, lineups:[{id, provider, region, regionCode, type, channels:[{position, name, logo, guideID}]}]}`.
Every digital channel is kept — `guideID` (the matched EPG id) is **nullable metadata, not a
filter**: channels the EPG feed doesn't carry still appear (logo + number, just an empty
schedule). Each channel carries its Digi `logo` URL. (The app derives a matched-only
`[guideID:position]` map from `channels` for `KnownChannelNumbers`.)

- **Producer:** `tools/digi-lineup-scraper/` — Node + Playwright. A real browser is required:
  digi.ro/grila serves the grid from a CSRF/cookie-protected `POST /api-get-grila` that plain
  curl can't reach (GET = empty table, POST = 403); the grid's **"Post"** column is the channel
  number, selectable per **county** (41 + București) and type. `scrape.mjs` captures the XHR
  payload → `digi-raw.json`; `build-lineups.mjs` matches scraped names → our XMLTV ids
  (`match.mjs` normalized-name index + `aliases.json` rebrand overrides) → `lineups.json` +
  `unmatched-report.json`. Selectors in `scrape.mjs` were authored without a live browser run —
  validate with `node scrape.mjs --county Cluj --headed` once and adjust.
- **CI:** `.github/workflows/lineups-update.yml` runs monthly and force-pushes `lineups.json` to
  the orphan **`lineup-data`** branch — a *separate* branch from `epg-data` on purpose, because
  `epg-update.yml` rewrites `epg-data` as orphan daily and would delete it. Has a sanity gate
  (won't publish a degenerate <50-number scrape over a good one).
- **App consumer:** `ChannelLineups.swift` (Services) holds the `ChannelLineupCatalog`/`ChannelLineup`
  model, `LineupClient` (actor — fetch/cache mirroring `EPGClient`, from the `lineup-data` raw URL),
  and `ChannelLineupStore` (`@MainActor @Observable`). The store persists the user's pick
  (`selectedChannelLineupID` in UserDefaults) and pushes the selected lineup's numbers into
  `KnownChannelNumbers.setActiveMapping(_:)`. `KnownChannelNumbers` now has a compiled
  `defaultMapping` (the 129-row table = offline fallback) and a thread-safe override
  (`OSAllocatedUnfairLock`, nonisolated because the Siri `TVChannelEntity` reads it off-main);
  `mapping`/`idByNumber`/`orderedIDs`/`number(for:)` all derive from the active override-or-default,
  so every consumer becomes lineup-aware with no call-site changes. `RemoteView` owns the store,
  calls `load()` on appear (before the EPG pre-warm), and the **gear menu → "Channel lineup"** item
  opens `LineupPickerView` (a searchable per-county sheet; "Built-in default" reverts to the table).
- **Not bundled:** `RemoteTV/Resources/lineups.json` is the scraper's seed/matcher input and the
  initial `lineup-data` content — it is NOT in the app bundle; the compiled `defaultMapping` is the
  offline fallback, so no app resource is needed.
- **Not yet wired:** the App Intents path (Siri "tune to channel") still uses the default table in
  background/extension launches — the store only applies the override in the running app UI.

## Info.plist requirements

- `NSBonjourServices` must contain `_samsungmsf._tcp`.
- `NSLocalNetworkUsageDescription` must be a human-readable string — it's shown in the
  permission prompt.
- `NSAppTransportSecurity.NSAllowsArbitraryLoads = true` so the WebSocket can open against
  a plain `ws://` TV without ATS blocking it.
- `CFBundleDisplayName` is **Zapy** — the user-facing app name (home screen + Siri primary).
  The Xcode target / `PRODUCT_NAME` / bundle id stay `RemoteTV` / `ro.remotetv.RemoteTV`
  (renaming them would churn provisioning, the App Group, and the control `kind` ids for no
  user benefit). `INAlternativeAppNames` re-registers "Zapy" with a pronunciation hint
  ("zap-ee") — the hint can only attach to an *alternative* name, so this is how Siri gets a
  pronunciation for the coined brand. (Earlier the name was "RemoteTV" with a "Cobalt"
  alias, because "remote TV" is ordinary TV vocabulary Siri transcribed poorly.)

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
`firstRegexMatch`, `TVIntentsController` (connect-on-demand + power/wake fallback),
`TVChannelEntity`/`TVAppEntity` catalogs; and in `TVScheduel/`: `XMLTVParser`, `XMLTVDate`.

Still untested (needs heavier mocks): the heartbeat ping classification, the voice
continuation lifecycle, `BonjourDiscoveryService`, `MicrophoneCaptureService`, and the
live `YouTubeLoungeClient` HTTP flow.
