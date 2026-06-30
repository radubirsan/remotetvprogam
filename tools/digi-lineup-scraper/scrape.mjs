// Scrapes digi.ro/grila for the per-county channel grid (the "Post" column = channel
// position/number) and writes the RAW result to digi-raw.json.
//
// WHY A REAL BROWSER: the grid is served by a CSRF/cookie-protected POST to
// `/api-get-grila` that plain curl cannot reach (GET returns an empty table, POST 403).
// Playwright runs the page's own JS, so the authenticated request "just works" — we then
// capture the XHR response payload (an HTML table) directly, which is far more robust than
// scraping the rendered DOM. We still fall back to DOM scraping if no XHR is captured.
//
// The page has three native <select>s (confirmed from the page source):
//   #services-tv-list-county   — county; values like "Bucuresti", "Cluj" (or "Toate")
//   #services-tv-list-signal   — "digital" | "analogic" | "satelit"
//   #services-tv-list-category — genre; left at its default ("Toate")
// Selecting a county fires the page's change handler, which POSTs to /api-get-grila.
//
// Output shape (digi-raw.json):
//   { "scrapedAt": "...", "counties": { "Cluj": [ { "post": 59, "name": "Digi 24 HD" }, ... ] } }
//
// Usage:
//   node scrape.mjs                 # all counties, headless, signal=digital
//   node scrape.mjs --county Cluj   # single county (debug)
//   node scrape.mjs --headed        # show the browser (local debugging)

import { chromium } from "playwright";
import { load as cheerioLoad } from "cheerio";
import { readFile, writeFile } from "node:fs/promises";

const GRILA_URL = "https://www.digi.ro/grila";
const API_PATH = "/api-get-grila";
const COUNTY_SEL = "#services-tv-list-county";
const SIGNAL_SEL = "#services-tv-list-signal";

const args = process.argv.slice(2);
const headed = args.includes("--headed");
const onlyCounty = (() => {
  const i = args.indexOf("--county");
  return i >= 0 ? args[i + 1] : null;
})();

const allCounties = JSON.parse(await readFile(new URL("./counties.json", import.meta.url)));
const counties = onlyCounty ? [onlyCounty] : allCounties;

/** Parse an `/api-get-grila` HTML fragment into [{post, name}] where `post` is the DIGITAL
 *  channel number. The table (`table-new table-tv-list`) has columns:
 *    Post (station name/logo) | Digital | Analogic | Satelit
 *  The header cells carry data-signal="digital|analogic|satelit"; we target the digital
 *  number per row by that attribute when present, else fall back to the 2nd column. The
 *  station name is the first column (text, or a logo's alt). Rows with no digital number
 *  (channel not carried on digital) are skipped. */
function parseGrilaHTML(html) {
  const $ = cheerioLoad(html);
  const rows = [];
  // Data rows = any .table-row that isn't the header (use children() so we don't depend on
  // the data-cell class name).
  $(".table-tv-list .table-row").each((_, el) => {
    const $el = $(el);
    if ($el.hasClass("table-header")) return;
    const cells = $el.children();
    if (cells.length < 2) return;

    const nameCell = cells.eq(0);
    const name = (nameCell.text().trim() || nameCell.find("img").attr("alt") || "").trim();

    let numText = $el.find('[data-signal="digital"]').first().text().trim();
    if (!numText) numText = cells.eq(1).text().trim(); // 2nd column = Digital
    const post = parseInt(numText, 10);

    if (name && Number.isFinite(post)) rows.push({ post, name });
  });
  return rows;
}

async function dismissCookieBanner(page) {
  for (const sel of [
    "#onetrust-accept-btn-handler",
    'button:has-text("Accept")',
    'button:has-text("De acord")',
    'button:has-text("Sunt de acord")',
  ]) {
    const btn = page.locator(sel).first();
    if (await btn.count().catch(() => 0)) {
      await btn.click({ timeout: 2000 }).catch(() => {});
      break;
    }
  }
}

/** Select a county. Playwright's selectOption fires native input+change, which triggers the
 *  page's /api-get-grila request — confirmed by the first run (85 responses seen). */
async function selectCounty(page, county) {
  await page.selectOption(COUNTY_SEL, county);
}

const browser = await chromium.launch({ headless: !headed });
const page = await browser.newPage({
  userAgent:
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
});

// Capture every /api-get-grila payload + count them (lets us tell "handler never fired"
// from "parser is wrong" in a single run).
let lastPayload = null;
let apiResponseCount = 0;
page.on("response", async (res) => {
  if (res.url().includes(API_PATH)) {
    apiResponseCount++;
    try {
      lastPayload = await res.text();
    } catch {
      /* ignore */
    }
  }
});

await page.goto(GRILA_URL, { waitUntil: "networkidle", timeout: 60000 });
await dismissCookieBanner(page);

// Confirm the controls exist — a clear early failure beats 42 silent timeouts.
const haveCounty = await page.locator(COUNTY_SEL).count().catch(() => 0);
console.log(`control check: ${COUNTY_SEL} present=${haveCounty > 0}`);
await page.selectOption(SIGNAL_SEL, "digital").catch((e) => console.log(`signal select: ${e.message}`));
await page.waitForTimeout(800);

const result = { scrapedAt: new Date().toISOString(), counties: {} };
let firstDiag = true;

for (const county of counties) {
  lastPayload = null;
  try {
    // Coordinate the selection with the XHR it triggers.
    const [resp] = await Promise.all([
      page.waitForResponse((r) => r.url().includes(API_PATH), { timeout: 20000 }).catch(() => null),
      selectCounty(page, county),
    ]);
    if (resp) {
      try {
        lastPayload = await resp.text();
      } catch {
        /* ignore */
      }
    }
    await page.waitForTimeout(400);

    let rows = lastPayload ? parseGrilaHTML(lastPayload) : [];
    if (!rows.length) rows = parseGrilaHTML(await page.content()); // DOM fallback

    // One-shot diagnostics on the first county: tells us exactly what to fix next.
    if (firstDiag) {
      firstDiag = false;
      console.log(`[diag] xhr captured for first county: ${resp ? "yes" : "no"}`);
      console.log(`[diag] payload length: ${lastPayload ? lastPayload.length : 0}`);
      if (lastPayload) {
        // A data-row slice (past the ~370-char header) so we can see the real row/cell markup.
        console.log(`[diag] data-row slice: ${lastPayload.slice(360, 2400).replace(/\s+/g, " ")}`);
      }
      console.log(`[diag] parsed rows: ${rows.length}`);
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
console.log(`/api-get-grila responses seen total: ${apiResponseCount}`);
if (empty.length) {
  console.warn(`EMPTY counties: ${empty.join(", ")}`);
  if (apiResponseCount === 0)
    console.warn("→ no XHR ever fired: the county <select> change isn't triggering the request (needs a submit click).");
  else
    console.warn("→ XHR fired but parsed 0 rows: parseGrilaHTML selectors need adjusting (see [diag] payload head).");
}
