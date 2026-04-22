# TODO

## Direct channel tuning

Jump straight to a channel number instead of spamming `KEY_CHUP` / `KEY_CHDOWN`.

Shared mechanics (both options):

- Add digit key codes to `TVCommand`: `KEY_0` … `KEY_9` plus `KEY_ENTER`.
- Send digits sequentially with ~150ms between presses — bursts faster than that get
  collapsed into a single input on most Tizen builds.
- End with `KEY_ENTER` (or let the TV auto-commit after the digit window closes).
- Skip dotted sub-channels (e.g. `42.1`) for the first pass — the `.` code
  (`KEY_PRECH` on some models, something else on others) isn't consistent across model
  years.

### Option A — text field + "Go" button

- Small section in `RemoteView` with a numeric `TextField` + a Go button.
- Minimal surface area, fits in the existing vertical layout.
- Less "TV-remote-y", but quickest to build.

### Option B — on-screen 0–9 numeric keypad

- Dedicated keypad view mirroring the physical remote's number pad (3×4 grid).
- More tactile / familiar; takes more screen real estate.
- Could share visual style with `DPadSection`.
