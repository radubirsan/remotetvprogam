# RemoteTV — Session Handoff

Snapshot for picking up the Samsung-style remote work in a fresh Claude Code session.
Read `CLAUDE.md` first for the project map, then this file for current state.

## Done (recent iterations, in order)

1. **Trackpad mode** — `TrackpadSection`, pure `TrackpadGestureMapper` + tests, `RemoteInputMode` enum (`@AppStorage("remoteInputMode")`).
2. **Samsung-style redesign** — replaced the original ScrollView-of-sections layout with `RemoteSamsungBody`, which mirrors the coordinates in `/RemoteSamsungStyle.swift`. Old section files (`StatusPill`, `AppsSection`, `BottomActionsSection`, `DPadSection`, `VolumeSection`, `ChannelSection`, `CommercialMuteSection`, `SniffLogSection`) are still in the project but no longer referenced.
3. **Status LED** — `RemoteStatusLED` replaces the static MIC dot. Grey / amber-pulse / blue-pulse / green / red; folds in `viewModel.lastError` as the red state.
4. **Compact mute pill** — `CompactCommercialMute` lives in `ToolbarItem(.topBarLeading)` next to the system back button. Shows a monospaced countdown when armed.
5. **Side-panel split layout** — `SidePanelMode` enum (`none` / `shortcuts` / `installedApps` / `sniffLog`), persisted via `@AppStorage("remoteSidePanel")`. HStack puts shortcuts/installedApps on the **left**, sniff log on the **right**. Mutually exclusive at the type level.
6. **Settings gear menu** in `ToolbarItem(.topBarTrailing)` — inline `Picker`s for Input mode and Side panel, plus Disconnect / Forget buttons. The in-canvas gear is gone.
7. **New TVCommand cases** — `.playPause = "KEY_PLAY"`, `.captions = "KEY_CAPTION"`. Encoder tests cover both.
8. **DPad tap-zone fix** — `DPadTapZone` private struct in `RemoteSamsungStyle.swift` replaces the static hint dots with real `Button`s for Up/Down/Left/Right. Existing swipe gesture stays as a fast-flick fallback.
9. **+25% button scale pass** — sizes, fonts, positions, body 760→880, canvas height 852→940. Rockers shifted apart (x=85 / x=255 at width 150) to avoid collision.
10. **HIG accessibility labels** plumbed through every atom (`CircleButton`, `Rocker`, `AppSlot`, `DPadTapZone`).

## Current step

The +25% button bump landed and **builds cleanly** (Xcode 15.2 here; tests can't run locally because Swift Testing requires Xcode 16+). On iPhone the visual increase is **~14%, not 25%** — `GeometryReader` scales the canvas down to fit, so growing the canvas height ate part of the bump. On iPad it'll be closer to a true 25%.

## Open loose ends / known issues

- **Visual scale on iPhone is partial.** To get closer to a real 25% bump on iPhone specifically: either keep canvas height at 852 (body overhangs ~88pt; brand label may clip) or shrink body width 340→320 to free vertical space without growing canvas.
- **DPad outer-ring swipes are not VoiceOver-actionable.** Fix: add `.accessibilityAction(named: "Up")` ×4 to the outer Circle in `RemoteSamsungStyle.swift` and mark it `.accessibilityElement(children: .ignore)`.
- **MIC label** under the status LED is now anachronistic. Could be replaced with state text ("READY" / "PAIR" / "CONN") if desired.
- **Dead files** — see list in item (2) above. None deleted because the user hasn't authorised cleanup.
- **AppsSection (UI file) is unused** but `TVApp` enum is still used by `RemoteSidePanelShortcuts`. Don't delete `TVApp.swift`.
- **Auto-load of installed apps** is still manual (user must open the Installed Apps side panel and tap Load). The 4-slot APP 1/APP 2 binding shows placeholders until then. Could trigger a refresh after first successful connect.

## Next step (suggested)

Pick **one** of these and run it to completion:

### Option A — Stronger visual button increase on iPhone
Goal: make the +25% bump actually look like +25% on iPhone.
Produce: a tweak to either `canvasHeight` (back to 852, accept brand-label clip risk) or `RemoteSamsungBody.width` (340→320 with re-laid horizontal positions). Verify with screenshots on iPhone 15 simulator that the buttons render visibly larger than before. Build clean.

### Option B — DPad VoiceOver fix
Goal: directional swipes on the DPad outer ring become navigable with VoiceOver.
Produce: edit to `DPad` in `RemoteSamsungStyle.swift` adding `.accessibilityElement(children: .ignore)` and four `.accessibilityAction(named: "Up"/"Down"/"Left"/"Right")` on the outer Circle. Quick manual test plan in the reply (Settings → Accessibility → VoiceOver → swipe up/down/left/right after focusing the DPad).

### Option C — Clean up unreferenced files
Goal: remove the eight legacy section files now that the Samsung-style body covers them.
Produce: delete `StatusPill.swift`, `AppsSection.swift`, `BottomActionsSection.swift`, `DPadSection.swift`, `VolumeSection.swift`, `ChannelSection.swift`, `CommercialMuteSection.swift`, `SniffLogSection.swift`. Strip their `PBXFileReference`, `PBXBuildFile`, `PBXGroup`, and `PBXSourcesBuildPhase` entries from `RemoteTV.xcodeproj/project.pbxproj`. Build clean. Note: `TVApp.swift` stays — used by `RemoteSidePanelShortcuts`.

### Option D — Auto-load installed apps after connect
Goal: APP 1 / APP 2 slots populate without forcing the user to open the side panel.
Produce: in `RemoteView`'s `.task`, after `await viewModel.connect()` succeeds, call `await viewModel.refreshInstalledApps()` if `viewModel.installedApps == nil` and `viewModel.lastError == nil`. Verify the slots populate without the side panel being open.

## File map (post-redesign)

```
RemoteTV/Features/Remote/
  RemoteView.swift                      ← orchestration + HStack split + toolbar
  RemoteSamsungBody.swift               ← inside-body content (340×880)
  RemoteSamsungStyle.swift  (root)      ← design source: theme + atoms + DPad tap zones
  RemoteStatusLED.swift                 ← LED dot
  CompactCommercialMute.swift           ← toolbar mute pill
  RemoteInputMode.swift                 ← dpad / trackpad enum
  SidePanelMode.swift                   ← none / shortcuts / installedApps / sniffLog
  RemoteSidePanelShortcuts.swift        ← left panel (TVApp.allCases)
  RemoteSidePanelInstalledApps.swift    ← left panel (dynamic loader)
  RemoteSidePanelSniffLog.swift         ← right panel
  TrackpadSection.swift                 ← circular trackpad surface
  TrackpadGestureMapper.swift           ← pure tap/swipe classifier
  RemoteViewModel.swift                 ← unchanged in this iteration
  RemoteToolbarMenu.swift               ← unused; retained for now
```

## Build / test commands

```bash
xcodebuild build -project RemoteTV.xcodeproj -scheme RemoteTV \
  -destination 'platform=iOS Simulator,name=iPhone 15'

# Tests require Xcode 16+ for the Testing module:
xcodebuild test  -project RemoteTV.xcodeproj -scheme RemoteTV \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```
