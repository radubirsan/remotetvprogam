# Handoff: Another Remote — iOS TV Remote App

## Overview
"Another Remote" is an iPhone app that controls a smart TV. It has these surfaces:
1. **Onboarding (Welcome)** — first-run screen with a fixed headline and an auto-looping showcase of the app's features (Remote, TV Guide, Mute Timer), plus a Get Started CTA.
2. **Remote** — a skeuomorphic on-screen remote (Samsung-style button layout) with power, mic/voice, number pad, D-pad, transport, volume/channel rockers, and quick-launch app slots.
3. **TV Guide** — a scrollable list of channels showing what's on now and next, with a featured "live now" card, search, and category filters.
4. **Mute Timer** — a countdown that silences the TV and auto-unmutes when it ends (shown as a feature preview in onboarding; build as a full control/sheet).

This document is self-sufficient: a developer who was not in the design conversation should be able to build the app from this README alone.

## About the Design Files
The files in this bundle are **design references created in HTML/React** — prototypes showing intended look and behavior, **not production code to ship directly**. The task is to **recreate these designs in SwiftUI** using native components, idiomatic state management, and the project's established patterns. A working SwiftUI starting point for the Remote screen is included (`RemoteSamsungStyle.swift`) — treat it as a reference implementation to extend, not gospel.

If you adopt an architecture (MVVM, TCA, etc.), wire the button actions and guide data through it rather than leaving them as empty closures.

## Fidelity
**High-fidelity (hifi).** Colors, typography, spacing, and layout are final. Recreate the UI pixel-perfectly. Exact values are listed under Design Tokens and per-component below. Target device: **iPhone 16 Pro, 393×852 pt logical**. Dark mode only.

---

## Screens / Views

### 0. Onboarding — Welcome (OnboardingScreen)
**Purpose:** First-run screen. Sells the value prop and previews features before the user connects a TV.

**Layout (top → bottom), vertical stack, 393 wide, full height:**
1. **Status bar** — 59 pt.
2. **Brand mark** — centered row: 26 pt rounded-square logo (accent gradient, `tv` icon) + "ANOTHER REMOTE" (13 pt, weight 700, tracking 1, `#9A9A9E`).
3. **Looping feature stage** (flex-grows to fill): a single centered preview illustration with an ambient accent glow behind it (280 pt blurred radial, `<accent>22`). Three previews **crossfade every 2600 ms** (opacity 0.6s ease + scale 0.94→1). Previews:
   - **Full Remote** — 150×250 mini remote (power, mic, D-pad+OK, two rockers).
   - **TV Guide** — 230×250 card titled "TV Guide" with 4 channel rows (badge, LIVE/NEWS/etc tag, title, accent progress bar).
   - **Mute Timer** — 210×250 card: "MUTE TIMER" label, 140 pt circular progress ring (accent stroke, 62% filled), centered mute icon + "2:48" + "until unmute", and 5m/10m/30m preset pills (middle selected = accent).
4. **Rotating caption** (min-height 64, centered, re-animates on change): accent eyebrow with dot (12 pt, 700) = feature label uppercased; description (14.5 pt, `#9A9A9E`, line-height 1.45). Copy:
   - Full Remote — "Every button from your physical remote — power, D-pad, volume, and voice."
   - TV Guide — "See what's on now and next across all your channels at a glance."
   - Mute Timer — "Silence the ad break and auto-unmute right when your show returns."
5. **Page indicator** — 3 dots, gap 7; active dot is a 20×6 accent pill, inactive 6×6 white-18%; animates width.
6. **Headline** — `<h1>` 28 pt, weight 700, line-height 1.15, letter-spacing −0.6, white, centered, text-wrap balance: **"Turn your iPhone into a remote for your Samsung TV"**.
7. **Primary CTA** — full-width 54 pt button, radius 16, fill `linear-gradient(180deg, accent, accent cc)`, dark text `#1A1A1D`, 17 pt weight 700, shadow `accent40`. Label "Get Started".
8. **Secondary link** — centered "Already set up? **Connect your TV**" (13.5 pt, `#7A7A7E` / link `#CFCFD2`).
9. **Home indicator** — 134×5 pill.

**Behavior:** the stage auto-advances on a 2.6 s timer; caption, glow tint, and dots stay in sync with the visible preview. In SwiftUI use a `Timer.publish` + `TabView(.page)` (or a manual index with `.transition(.opacity.combined(with: .scale))`). Respect `accessibilityReduceMotion` — if on, hold the first card or use plain crossfades without scale. "Get Started" advances to TV connection/pairing; "Connect your TV" jumps straight there.

### 1. Remote (RemoteSamsungStyleView)
**Purpose:** Primary control surface — the user taps physical-style buttons to drive the TV.

**Layout:** A single rounded-rectangle "remote body" centered on a near-black background.
- Screen: 393×852 pt.
- Remote body: 340 pt wide × 760 pt tall, corner radius 56, offset x = 26.5, y = 60.
- All controls are absolutely positioned via `.position(x:y:)` relative to the body's top-left.
- A settings gear (44×44) floats top-right of the screen, outside the body, at x = W−32, y = 76.

**Components** (all sizes are the *visible* button diameter; every interactive element is ≥ 44 pt to satisfy HIG):

| Element | Size (pt) | Position (center, rel. to body) | Icon (SF Symbol) | Notes |
|---|---|---|---|---|
| Power | 56 | (68, 64) | `power` (heavy, 22) | Icon tinted red `#E63946` |
| MIC label | — | (170, 50) | dot + "MIC" text | Non-interactive label, color `#5A5A5E` |
| Mic/Voice | 56 | (272, 64) | `mic` (20) | |
| Number pad (123) | 56 | (68, 138) | `gearshape` (13) + "123" text | |
| D-pad outer | 220 | (170, 310) | — | 4-way swipe surface (DragGesture) + 4 hint dots near rim |
| D-pad OK (inner) | 96 | center of D-pad | "OK" text (16, semibold) | |
| Back | 56 | (68, 498) | `arrow.uturn.backward` (19) | |
| Home | 64 | (170, 498) | `house.fill` (22) | |
| Play/Pause | 56 | (272, 498) | `playpause.fill` (18) | |
| Volume rocker | 120×52 | (100, 588) | `minus` / `plus` (18) | Capsule split into two tap halves |
| Channel rocker | 120×52 | (240, 588) | `chevron.up` / `chevron.down` (16) | Capsule split into two tap halves |
| CC/AD label | — | (100, 624) | "CC/AD" + `speaker.slash` | Non-interactive, color `#7A7A7A` |
| App slot 1 | 56 | (68, 684) | "APP" / "1" text | Round button |
| Live TV slot | 64 | (170, 684) | "LIVE" / "TV" text | Round button, hero slot |
| App slot 2 | 56 | (272, 684) | "APP" / "2" text | Round button |
| Brand label | — | (170, RH−28) | "ANOTHER REMOTE" | Tracking 2, color `#5A5A5E` |

**Button visual treatment (skeuomorphic):**
- Face fill: radial gradient, light center `#232327` → mid `#161618` → dark edge `#0C0C0E`, center point (0.35, 0.30).
- Border: `Circle().stroke(white 5%, 0.5pt)`.
- Drop shadow: black 50%, radius 3, y-offset 2.
- D-pad outer uses a wider radial gradient (radius ~140); inner OK uses a lighter radial (center `#2C2C30`).

### 2. TV Guide (TVGuideScreen)
**Purpose:** Browse channels and see current/upcoming programming; jump to a channel.

**Layout (top → bottom), full-bleed vertical stack, 393 wide:**
1. **Status bar** — 59 pt tall, "9:41" left, signal/battery right, white.
2. **Header** — padding 4/20/12. Title "TV Guide" (28 pt, weight 700, letter-spacing −0.5, white) with subtitle "Tuesday, June 17 · 9:41 AM" (12.5 pt, `#7A7A7E`). Settings gear (40 pt round, `gearshape`) top-right.
3. **Search bar** — 40 pt tall, radius 12, fill white 5%, magnifier icon + placeholder "Search channels & shows" (`#6A6A6E`).
4. **Category chips** — horizontal row, gap 8. Pills 6×14 padding, radius 999, 12.5 pt weight 600. First chip ("All") uses accent fill with dark text `#1A1A1D`; others white-6% fill, text `#B0B0B4`. Labels: All, Live, Movies, Sports, News, Kids.
5. **Featured "Live Now" card** — 120 pt tall, radius 18, padding 16. Background `linear-gradient(135deg, <channelTint>cc 0%, #1A1A1D 75%)`. Top-left "● LIVE NOW" badge (red dot `#FF4444` + glow, white text 10 pt, on black-30% pill). Top-right "CH 4 · Apex Sports" (11 pt, white 85%). Bottom: program title (18 pt, 700, white, subtle text-shadow) + "8:30 – 10:30 · Ends in 79 min" (12 pt, white 85%).
6. **List header** — "ALL CHANNELS" (11 pt, 700, tracking 1.4, `#5A5A5E`) left; "On Now ▾" (11 pt, 600, accent) right.
7. **Channel list** — vertical, each row 12 pt vertical padding, separated by a 1 pt white-5% bottom border. See ChannelRow below.
8. **Bottom tab bar** — 80 pt tall, top border white 6%, background `rgba(12,12,14,0.9)` + blur. Four tabs evenly spaced: Remote (`tv` icon), Guide (active), Apps, Settings. Active tab uses accent color; inactive `#6A6A6E`. Labels 10 pt weight 600.
9. **Home indicator** — 134×5 pt pill, white 50%, 8 pt from bottom.

**ChannelRow component** (flex row, gap 12):
- **Channel badge** (52 pt column): rounded-square 44×44, radius 12, fill `linear-gradient(145deg, <tint>, <tint>99)`, channel number centered (16 pt, weight 800, white), colored shadow `<tint>40`. Below: channel name (8.5 pt, weight 600, `#6A6A6E`, centered, max 2 lines).
- **Program info** (flex 1):
  - Row of: category tag pill (9 pt, 700, uppercase — "Live" tag uses red-tinted bg `rgba(230,57,70,0.18)` + text `#FF6B6B`; others white-6% bg + `#9A9A9E`) and time range "9:00 – 10:00" (11 pt, `#6A6A6E`, tabular nums).
  - Program title (14.5 pt, weight 600, `#E8E8EA`, single line ellipsis).
  - Progress bar: 3 pt tall, radius 2, track white 8%, fill accent at `prog` fraction (0–1).
  - "Next:" line (11 pt, `#5A5A5E`) with next start time in `#7A7A7E` weight 600.

---

## Interactions & Behavior
- **Remote buttons:** each fires an action closure. Wire to your TV-control transport (IR/Wi-Fi/CEC). Provide `.sensoryFeedback(.impact, ...)` or `UIImpactFeedbackGenerator(.soft)` on press.
- **D-pad:** outer ring is a `DragGesture(minimumDistance: 12)` — on end, compare `|dx|` vs `|dy|` to emit up/down/left/right. Inner circle is the OK button.
- **Rockers:** capsule split into two equal tap halves (top = minus / channel-up, bottom = plus / channel-down per labels).
- **TV Guide rows:** tapping a row should tune the TV to that channel (and ideally pop back to the Remote tab or show a "now playing" state). Tapping the featured card tunes to the live channel.
- **Category chips:** filter the channel list by category; selected chip gets the accent fill.
- **Search:** filters channels/shows by text.
- **Tab bar:** switches between Remote / Guide / Apps / Settings surfaces.
- **Settings gear:** presents a settings sheet (rows: Haptic feedback, Sound on press, Brightness control, Voice assistant; plus a connected-device card "Living Room TV").
- **Progress bars** should advance in real time based on program start/end vs. current time.

## State Management
Suggested state:
- `connectedDevice: TVDevice?` — name, connection type, volume level.
- `accent: AccentColor` — theme accent (see tokens). Drives progress bars, active tab, selected chip, primary buttons.
- `selectedTab: Tab` — `.remote | .guide | .apps | .settings`.
- `guideCategory: Category` — current filter, default `.all`.
- `searchText: String`.
- `channels: [Channel]` — each with `number, name, tint, nowProgram, nextProgram`. `Program` has `title, start, end, progress, category`.
- `now: Date` — drives progress fractions and "ends in N min"; tick on a timer.

## Design Tokens

**Colors**
| Token | Hex |
|---|---|
| Screen bg (top→bottom) | `#1A1A1D` → `#0A0A0B` (radial) / guide `#121214` → `#08080A` (linear) |
| Remote body | `#1F1F22` → `#0E0E10` |
| Button face center / mid / edge | `#232327` / `#161618` / `#0C0C0E` |
| Primary text | `#E8E8EA` |
| Secondary text | `#9A9A9E` |
| Tertiary / labels | `#6A6A6E`, `#5A5A5E` |
| Power red / Live | `#E63946`, badge dot `#FF4444`, live text `#FF6B6B` |
| Connected dot (green) | `#34D160` (rgb 0.20, 0.82, 0.38) |
| Hairline border | white @ 5% |

**Accent options** (user-selectable; default Ember):| Name | hi | lo |
|---|---|---|
| Ember (default) | `#FF6B5A` | `#C8281A` |
| Amber | `#FFB86B` | `#C8821A` |
| Cyan | `#6BD4FF` | `#1A8EC8` |
| Violet | `#B86BFF` | `#7028C8` |
| Mint | `#6BFFAA` | `#1AC876` |

**Channel tints** (guide badges): `#E63946 #2A9D8F #E9C46A #457B9D #F4A261 #8367C7 #EF476F #06A77D`

**Typography** — system font (SF Pro). Sizes/weights are listed inline per component above. Use tabular/monospaced numerals for times and channel numbers.

**Radii:** buttons = circle; remote body 56; cards 18; search 12; chips 999; channel badge 12; tag pill 5–6.

**Shadows:** button `black 50%, r3, y2`; D-pad outer `black 60%, r6, y4`; remote body `black 60%, r22, y14`; card colored glow `<tint>40`.

**Spacing:** screen side padding 20; remote inner insets 40 (sides). Tab bar 80 tall. Status bar 59 tall.

## Assets
No raster assets. All icons are **SF Symbols** (`power`, `mic`, `gearshape`, `house.fill`, `playpause.fill`, `arrow.uturn.backward`, `chevron.up/down`, `plus`, `minus`, `speaker.slash`, `tv`, `magnifyingglass`). Channel badges are number text on a colored gradient — no logos. **Do not** use any real broadcaster or streaming-service branding; all channel/app names here are placeholders.

## Files
In this bundle:
- `RemoteSamsungStyle.swift` — working SwiftUI reference implementation of the Remote screen (HIG-compliant sizes, accessibility labels). Extend this.
- `Another Remote.html` — full interactive prototype (open in a browser). Contains all four remote variations + the Onboarding and TV Guide screens. Use it to see exact spacing, colors, and behavior.
- `remote-samsung.jsx` — source for the Remote (Design D) layout.
- `remote-onboarding.jsx` — source for the Onboarding screen (looping feature stage, mute-timer & guide previews, headline, CTA).
- `remote-tvguide.jsx` — source for the TV Guide screen (channel data, row layout, featured card).
- `icons.jsx` — icon path reference (maps to SF Symbols above).

Open `Another Remote.html` first for the visual source of truth; Onboarding and TV Guide are under the "App Screens" section.
