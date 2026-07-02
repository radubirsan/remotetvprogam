// Turns digi-raw.json (from scrape.mjs) into lineups.json (consumed by the app) plus an
// unmatched-report.json for review. One lineup per county (digital).
//
// Schema v2: each lineup has a `channels` array holding EVERY digital channel — matched to an
// EPG id or not. The app shows all of them (unmatched ones just have no programme schedule);
// `guideID` is nullable metadata, no longer a filter. Each channel carries its Digi logo.
//
// Run after scrape.mjs:  node build-lineups.mjs

import { readFile, writeFile } from "node:fs/promises";
import { buildMatcher } from "./match.mjs";

const slug = (s) =>
  s
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");

const raw = JSON.parse(await readFile(new URL("./digi-raw.json", import.meta.url)));
const matcher = await buildMatcher();

const lineups = [];
const unmatched = {}; // county -> ["pos name"]
const unmatchedCounts = {}; // name -> count (prioritise alias additions)

for (const [county, rows] of Object.entries(raw.counties)) {
  if (!rows.length) continue;
  const channels = [];
  const seenPos = new Set();
  for (const { post, name, logo } of rows) {
    if (seenPos.has(post)) continue; // dedupe by position (first wins)
    seenPos.add(post);
    const guideID = matcher.match(name) || null;
    channels.push({ position: post, name, logo: logo || null, guideID });
    if (!guideID) {
      (unmatched[county] ??= []).push(`${post} ${name}`);
      unmatchedCounts[name] = (unmatchedCounts[name] ?? 0) + 1;
    }
  }
  channels.sort((a, b) => a.position - b.position);
  lineups.push({
    id: `digi-${slug(county)}-digital`,
    provider: "Digi",
    region: county,
    regionCode: slug(county),
    type: "digital",
    channels,
  });
}

const catalog = {
  schemaVersion: 2,
  generatedAt: new Date().toISOString(),
  source: `digi.ro/grila scrape ${raw.scrapedAt}`,
  lineups: lineups.sort((a, b) => a.id.localeCompare(b.id)),
};

await writeFile(new URL("./lineups.json", import.meta.url), JSON.stringify(catalog, null, 2) + "\n");

const ranked = Object.entries(unmatchedCounts).sort((a, b) => b[1] - a[1]);
await writeFile(
  new URL("./unmatched-report.json", import.meta.url),
  JSON.stringify({ byCounty: unmatched, byNameFrequency: ranked }, null, 2) + "\n"
);

const totalChannels = lineups.reduce((n, l) => n + l.channels.length, 0);
const matched = lineups.reduce((n, l) => n + l.channels.filter((c) => c.guideID).length, 0);
console.log(`wrote lineups.json — ${lineups.length} lineups, ${totalChannels} channels (${matched} with EPG match)`);
console.log(`unmatched distinct names: ${ranked.length} (shown too, just no schedule; see unmatched-report.json)`);
if (ranked.length) {
  console.log("top unmatched (add to aliases.json to give them EPG):");
  for (const [name, n] of ranked.slice(0, 15)) console.log(`  ${n}×  ${name}`);
}
