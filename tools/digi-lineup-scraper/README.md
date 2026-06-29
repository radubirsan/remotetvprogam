# Digi lineup scraper

Produces `lineups.json` — the per-county channel-number map the app uses instead of the
hard-coded `KnownChannelNumbers` table — by scraping **digi.ro/grila**.

## Why a headless browser

The grid is served by a CSRF/cookie-protected `POST /api-get-grila` that plain `curl`
cannot reach (GET returns an empty table; POST returns `403`). A real browser (Playwright)
runs the page's own JS so the authenticated request succeeds; `scrape.mjs` then captures the
XHR response payload directly (more robust than scraping the rendered DOM), with a DOM-scrape
fallback. The grid's **"Post"** column is the channel position/number.

## Pipeline

```
scrape.mjs        digi.ro/grila ──(per county)──►  digi-raw.json   { county: [{post,name}] }
build-lineups.mjs digi-raw.json ──(match.mjs)───►  lineups.json    + unmatched-report.json
```

`match.mjs` maps a scraped display-name ("Digi 24 HD") to our XMLTV id ("Digi.24.HD.ro") via
a normalized-name index plus `aliases.json` overrides for rebrands. Anything unmatched lands
in `unmatched-report.json`, ranked by frequency — add the top entries to `aliases.json` and
re-run `build-lineups.mjs` (no re-scrape needed).

## Run locally

```sh
cd tools/digi-lineup-scraper
npm install
npx playwright install chromium
node scrape.mjs --county Cluj --headed   # debug one county, visible browser
node scrape.mjs                          # all counties, headless
node build-lineups.mjs                   # -> lineups.json + unmatched-report.json
```

## ⚠️ First-run validation

The DOM selectors in `scrape.mjs` (`selectCounty`, the cookie banner, the `.table-tv-list`
row shape in `parseGrilaHTML`) are based on the page structure as observed, but were authored
without a live browser run. **Validate with `--county Cluj --headed` once** and adjust the
selectors if a county comes back empty. The capture-the-XHR path is the primary mechanism; the
parser reads the first numeric cell as the position and the longest text cell as the name, so
it tolerates column drift.

## Publishing

CI (`.github/workflows/lineups-update.yml`) runs this monthly and force-pushes `lineups.json`
to the orphan **`lineup-data`** branch — a *separate* branch from `epg-data` on purpose:
`epg-update.yml` rewrites `epg-data` as an orphan daily and would otherwise delete this file.
The app reads it from that branch's raw URL (see `LineupClient`).
