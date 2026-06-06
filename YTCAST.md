# Casting a specific YouTube video to a Samsung Tizen TV

How RemoteTV's **YouTube Cast** button opens an *exact* video (+ playlist + start
timestamp), **fullscreen**, on the TV's YouTube app — no on-TV pairing code.

> TL;DR: open YouTube as a **normal app** (so the TV doesn't pop Multi View), read the
> `screenId` from its **DIAL state**, then drive playback over the private **YouTube Lounge
> API**. The DIAL *launch* protocol is deliberately **not** used — see the appendix for why.

---

## What does *not* work (and why)

| Approach | Result | Why |
|---|---|---|
| Plain app-launch alone (`POST :8001/api/v2/applications/<id>`) | Opens YouTube **home screen** | No way to pass a video; it only foregrounds the app. |
| DIAL launch with a `v=<id>` body | App opens, **ignores the video** | Modern YouTube dropped the legacy local deeplink; the video must arrive over Lounge. |
| **DIAL launch** (to open the app at all) | Pops **Samsung Multi View** | A DIAL "cast" launch arriving while another source (live TV / Netflix) is active makes the TV show YouTube + the old source side by side. |
| AirPlay the watch URL | Idle AirPlay screen | AirPlay relays a *live media element*, not a web URL. (A `WKWebView` playing the page *can* be AirPlayed — the separate "AirPlay (YouTube)" button — but that's not this.) |
| `ed.apps.launch` over the control WebSocket | Silently no-ops | Recent Tizen ignores the frame. |

So the shipped path is: **normal app-launch to open fullscreen, Lounge to play.**

---

## The working pipeline

```
tap YouTube Cast
   │
   ├─1─ foreground YouTube         POST http://<ip>:8001/api/v2/applications/111299001912
   │      (NORMAL app-launch)      → 200, opens fullscreen / single-view (no Multi View)
   │
   ├─2─ read screenId              GET  http://<ip>:8080/ws/app/YouTube   (DIAL *state*, poll)
   │                               → <additionalData>…<screenId>…</screenId>
   │
   ├─3─ lounge token               POST https://www.youtube.com/api/lounge/pairing/get_lounge_token_batch
   │      body screen_ids=<id>     → { "screens":[{ "loungeToken":"…" }] }
   │
   ├─4─ bind session (RID=1)       POST https://www.youtube.com/api/lounge/bc/bind?<params>
   │      empty body               → scrape  "c","<SID>"   and  "S","<gsessionid>"
   │
   └─5─ setPlaylist (RID=2)        POST https://www.youtube.com/api/lounge/bc/bind?SID=…&gsessionid=…
          form body                → exact video plays fullscreen on the TV
```

Code: `SamsungTVService.castYouTubeVideo(videoId:listId:startSeconds:)`.

---

## Step-by-step

### 1. Foreground YouTube — the **normal** app-launch, not DIAL

```
POST http://<ip>:8001/api/v2/applications/111299001912     # 111299001912 = YouTube (TVApp.youtube.appID)
```

This is the *same* call as the "YouTube" shortcut button (`TVService.launch(appID:)`). It
opens YouTube fullscreen, single-view. We use this **instead of** a DIAL launch specifically
to avoid Samsung **Multi View** (see appendix). Lounge does the actual "play this video", so
we don't need DIAL's launch semantics at all — only its *state* document, below.

### 2. screenId from the DIAL **state** document (a GET)

YouTube registers its screen with the TV's DIAL/MDX service whenever it's running, no matter
how it was launched. So we just GET the DIAL state and scrape the id:

```
GET http://<ip>:8080/ws/app/YouTube
→ <service xmlns="urn:dial-multiscreen-org:schemas:dial" dialVer="2.2">
     <name>YouTube</name><state>running</state>…
     <additionalData><screenId>820345c9…8434</screenId></additionalData>
   </service>
```

Gotchas:
- The base URL varies by model. We probe a small candidate list (`dialBaseURLs(ip:)`);
  `:8080/ws/app/` answers on our test set. A GET (read-only) never triggers Multi View.
- The `screenId` appears a **beat after** launch — the first GET often lacks `additionalData`.
  We poll up to 10×/0.8s. See `fetchYouTubeScreenId()`.
- Send the GET **without** an Origin header (only state-changing POSTs are CSRF-gated; a
  stray Origin can itself trip a 403).

### 3. Lounge token

```
POST https://www.youtube.com/api/lounge/pairing/get_lounge_token_batch
Content-Type: application/x-www-form-urlencoded
Body: screen_ids=<screenId>
→ { "screens": [ { "loungeToken": "<token>", "expiration": <ms> } ] }
```

### 4. Bind session — get `SID` + `gsessionid`

All params go in the **query string**; the **body is empty** (so no Content-Type).

```
POST https://www.youtube.com/api/lounge/bc/bind
        ?CVER=1&RID=1&VER=8
        &app=youtube-desktop&device=REMOTE_CONTROL&id=remote
        &name=RemoteTV&loungeIdToken=<token>
```

The response is Google's chunked "browser channel" format (a length number, then nested
JSON arrays). We don't parse it structurally — we scrape:

- `SID`        ← first `"c","<value>"`
- `gsessionid` ← first `"S","<value>"`

### 5. setPlaylist — actually play the video

Session ids in the query; the command in a form body.

```
POST https://www.youtube.com/api/lounge/bc/bind
        ?CVER=1&RID=2&VER=8&SID=<sid>&gsessionid=<gsid>&loungeIdToken=<token>
Content-Type: application/x-www-form-urlencoded

count=1
req0__sc=setPlaylist          # NOTE: double underscore (key is "_sc")
req0_videoId=<videoId>        # single underscore for data fields
req0_currentTime=<seconds>
req0_currentIndex=0
req0_videoIds=<videoId>       # single id so playback starts even with no list
req0_listId=<listId>          # optional; the RD… radio mix
```

The `req0__sc` (double `_`) vs `req0_videoId` (single `_`) distinction is real and easy to
get wrong — `casttube` and `ytcast` disagree; `ytcast` is correct.

### Headers on every Lounge request

```
Origin: https://www.youtube.com
User-Agent: Mozilla/5.0 (… Chrome/96 …)     # a desktop UA; the endpoint is pickier otherwise
```

---

## Where it lives in the code

| Piece | Location |
|---|---|
| URL parse (`v` / `list` / `t`) | `RemoteViewModel.parseYouTube(from:)` |
| Button action | `RemoteViewModel.castYouTube()` → `TVService.castYouTubeVideo(videoId:listId:startSeconds:)` |
| Orchestration (launch → screenId → Lounge) | `SamsungTVService.castYouTubeVideo(...)` |
| screenId scrape | `SamsungTVService.fetchYouTubeScreenId()`, `dialBaseURLs(ip:)` |
| Lounge protocol (token/bind/setPlaylist) | `struct YouTubeLoungeClient` (bottom of `SamsungTVService.swift`) |
| UI button | `RemoteSidePanelShortcuts` → "YouTube Cast" |

Every stage logs to the in-app **Sniff Log** (and the Xcode console), so a failure points at
the exact step:

```
[Launch] 111299001912: HTTP 200 body=true
<- DIAL YouTube screenId=820345c9acb3…
 . Lounge: connecting (screenId=820345c9acb3…)
 . Lounge: setPlaylist sent (v=qUundAa9j4M, t=2649)
```

---

## ⚠️ Fragility

The Lounge API is **undocumented and private**. Google can change params, the bind format,
or the trusted-origin list at any time and this breaks with no warning. If casting fails,
read the Sniff Log to see which stage broke:

- `No YouTube screenId in DIAL additionalData` → the running app didn't publish a screenId
  (firmware change). Fallback: a one-shot DIAL launch to register the screen, or the manual
  pairing-code flow (`get_screen?pairing_code=<code>`).
- `Lounge error: lounge token HTTP 4xx` → screenId rejected (token params changed).
- `Lounge error: no SID/gsessionid in bind response` → bind format changed.
- `Lounge error: setPlaylist HTTP 4xx` → token+bind fine, only the play command is off.

---

## Appendix — dead ends & hard-won facts

Things we burned time on; kept here because the next person (or a firmware change) may need
them.

**Samsung Multi View is the reason we don't DIAL-launch.** A DIAL launch is treated as an
incoming *cast*; when another source is foreground, the TV splits the screen (YouTube + live
TV/Netflix). It is a TV-level feature with no Lounge/DIAL override. Opening YouTube as a
normal app sidesteps it entirely. (Stopping/cold-restarting the app does **not** help — the
launch *mechanism* is the trigger, not the app's run state.)

**If you ever DO need the DIAL launch** (e.g. screenId stops appearing), these were the
findings:
- Endpoint is **port 8080, path `/ws/app/` (singular)**. The plural `:8080/ws/apps/` is a
  *different* Samsung service that 403s POSTs — a misleading 403 that cost an afternoon.
  Port 80 was closed on our set.
- 2021+ firmware added a **CSRF mitigation**: a launch POST with no/foreign `Origin` gets a
  bare **403**. Send the app's own cast origin (`Origin: https://www.youtube.com`). Do *not*
  send an arbitrary origin — a present-but-unwhitelisted one is actively rejected, unlike a
  missing one.
- DIAL §6.1.2: a non-empty launch body must be `text/plain; charset=utf-8` (Samsung 403s any
  other Content-Type). And keep the body **empty** — a `v=<id>` deeplink opens the app into a
  split onboarding pane.
- The launch 201's body/Location is the **run-instance URL** (`…/ws/apps/YouTube/run`, plural);
  `DELETE` it to stop the app.

---

## References

Wire format assembled from (thanks to their authors):

- Samsung DIAL CSRF/Origin reverse-engineering — https://www.gabriel.urdhr.fr/2021/03/22/samsung-tv-dial/
- `ytcast` (Go, DIAL→Lounge) — https://github.com/MarcoLucidi01/ytcast (`youtube/remote.go`)
- `casttube` (Python, used by pychromecast) — https://github.com/ur1katz/casttube
- DIAL 2nd-Screen Protocol spec — https://www.dial-multiscreen.org/
- "I Built a TV That Plays All of Your Private YouTube Videos" — https://bugs.xdavidhu.me/google/2021/04/05/i-built-a-tv-that-plays-all-of-your-private-youtube-videos/
