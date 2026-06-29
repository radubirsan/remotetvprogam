// Scrapes digi.ro/grila for the per-county channel grid (the "Post" column = channel
// position/number) and writes the RAW result to digi-raw.json.
//
// WHY A REAL BROWSER: the grid is served by a CSRF/cookie-protected POST to
// `/api-get-grila` that plain curl cannot reach (GET returns an empty table, POST 403).
// Playwright runs the page's own JS, so the authenticated request "just works" — we then
// capture the XHR response payload (an HTML table) directly, which is far more robust than
// scraping the rendered DOM. We still fall back to DOM scraping if no XHR is captured.
//
// Output shape (digi-raw.json):
//   { "scrapedAt": "...", "counties": { "Cluj": [ { "post": 59, "name": "Digi 24 HD" }, ... ], ... } }
//
// Usage:
//   node scrape.mjs                 # all counties, headless
//   node scrape.mjs --county Cluj   # single county (debug)
//   node scrape.mjs --headed        # show the browser (local debugging)

import { chromium } from "playwright";
import { load as cheerioLoad } from "cheerio";
import { readFile, writeFile } from "node:fs/promises";

const GRILA_URL = "https://www.digi.ro/grila";
const API_PATH = "/api-get-grila";

const args = process.argv.slice(2);
const headed = args.includes("--headed");
const onlyCounty = (() => {
  const i = args.indexOf("--county");
  return i >= 0 ? args[i + 1] : null;
})();

const allCounties = JSON.parse(await readFile(new URL("./counties.json", import.meta.url)));
const counties = onlyCounty ? [onlyCounty] : allCounties;

/** Parse an `/api-get-grila` HTML fragment into [{post, name}]. The table uses the
 *  `table-new table-tv-list` structure with a leading "Post" (position) column. We read the
 *  first numeric cell as the position and the longest text cell as the channel name, so we
 *  don't depend on an exact column count that may drift. */
function parseGrilaHTML(html) {
  const $ = cheerioLoad(html);
  const rows = [];
  $(".table-tv-list .table-row, table tr").each((_, el) => {
    if ($(el).hasClass("table-header") || $(el).find("th").length) return;
    const cells = $(el)
      .find(".table-cell, .table-head, td")
      .map((__, c) => $(c).text().trim())
      .get()
      .filter((t) => t.length);
    if (!cells.length) return;
    const post = cells.map((c) => parseInt(c, 10)).find((n) => Number.isFinite(n));
    // Channel name: the longest non-numeric cell (logos sometimes leave an empty cell).
    const name = cells
      .filter((c) => !/^\d+$/.test(c))
      .sort((a, b) => b.length - a.length)[0];
    if (Number.isFinite(post) && name) rows.push({ post, name });
  });
  return rows;
}

async function dismissCookieBanner(page) {
  for (const sel of [
    'button:has-text("Accept")',
    'button:has-text("De acord")',
    'button:has-text("Sunt de acord")',
    "#onetrust-accept-btn-handler",
  ]) {
    const btn = page.locator(sel).first();
    if (await btn.count().catch(() => 0)) {
      await btn.click({ timeout: 2000 }).catch(() => {});
      break;
    }
  }
}

/** Select a county in the region control. The page uses a `.regions` widget; we try a native
 *  <select> first, then a custom dropdown (click to open, click the matching option). */
async function selectCounty(page, county) {
  // 1) native <select>
  const select = page.locator("select.regions, select[name*=region], select[name*=judet]").first();
  if (await select.count().catch(() => 0)) {
    await select.selectOption({ label: county }).catch(async () => {
      await select.selectOption(county).catch(() => {});
    });
    return;
  }
  // 2) custom dropdown widget
  const opener = page.locator(".regions, [class*=region]").first();
  if (await opener.count().catch(() => 0)) {
    await opener.click({ timeout: 3000 }).catch(() => {});
    const option = page.locator(`text="${county}"`).first();
    await option.click({ timeout: 3000 }).catch(() => {});
  }
}

const browser = await chromium.launch({ headless: !headed });
const page = await browser.newPage({
  userAgent:
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
});

// Capture every /api-get-grila payload as it arrives.
let lastPayload = null;
page.on("response", async (res) => {
  if (res.url().includes(API_PATH)) {
    try {
      lastPayload = await res.text();
    } catch {
      /* ignore */
    }
  }
});

await page.goto(GRILA_URL, { waitUntil: "networkidle", timeout: 60000 });
await dismissCookieBanner(page);

const result = { scrapedAt: new Date().toISOString(), counties: {} };

for (const county of counties) {
  lastPayload = null;
  try {
    await selectCounty(page, county);
    // Wait for the XHR triggered by the selection (or a DOM update).
    await page
      .waitForResponse((r) => r.url().includes(API_PATH), { timeout: 15000 })
      .catch(() => {});
    await page.waitForTimeout(1200);

    let rows = lastPayload ? parseGrilaHTML(lastPayload) : [];
    if (!rows.length) {
      // Fallback: scrape the rendered DOM.
      const html = await page.content();
      rows = parseGrilaHTML(html);
    }
    result.counties[county] = rows;
    console.log(`${county}: ${rows.length} channels`);
  } catch (err) {
    console.error(`${county}: FAILED — ${err.message}`);
    result.counties[county] = [];
  }
}

await browser.close();
await writeFile(new URL("./digi-raw.json", import.meta.url), JSON.stringify(result, null, 2));

const total = Object.values(result.counties).reduce((n, r) => n + r.length, 0);
const empty = Object.entries(result.counties).filter(([, r]) => !r.length).map(([c]) => c);
console.log(`\nwrote digi-raw.json — ${total} rows across ${counties.length} counties`);
if (empty.length) console.warn(`EMPTY counties (selector/param needs review): ${empty.join(", ")}`);
