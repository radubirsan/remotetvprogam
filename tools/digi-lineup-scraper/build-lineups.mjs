// Turns digi-raw.json (from scrape.mjs) into lineups.json (consumed by the app) plus an
// unmatched-report.json for manual review. One lineup per county (digital).
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
const unmatched = {}; // county -> [names]
const unmatchedCounts = {}; // normalized name -> count (to prioritise alias additions)

for (const [county, rows] of Object.entries(raw.counties)) {
  if (!rows.length) continue;
  const numbers = {};
  for (const { post, name } of rows) {
    const id = matcher.match(name);
    if (id) {
      // First occurrence wins (HD/SD both map distinctly; dupes are rare).
      if (!(id in numbers)) numbers[id] = post;
    } else {
      (unmatched[county] ??= []).push(`${post} ${name}`);
      unmatchedCounts[name] = (unmatchedCounts[name] ?? 0) + 1;
    }
  }
  lineups.push({
    id: `digi-${slug(county)}-digital`,
    provider: "Digi",
    region: county,
    regionCode: slug(county),
    type: "digital",
    numbers: Object.fromEntries(Object.entries(numbers).sort((a, b) => a[1] - b[1])),
  });
}

const catalog = {
  schemaVersion: 1,
  generatedAt: new Date().toISOString(),
  source: `digi.ro/grila scrape ${raw.scrapedAt}`,
  lineups: lineups.sort((a, b) => a.id.localeCompare(b.id)),
};

await writeFile(new URL("./lineups.json", import.meta.url), JSON.stringify(catalog, null, 2) + "\n");

// Unmatched report — sorted by frequency so the most impactful aliases.json additions come first.
const ranked = Object.entries(unmatchedCounts).sort((a, b) => b[1] - a[1]);
await writeFile(
  new URL("./unmatched-report.json", import.meta.url),
  JSON.stringify({ byCounty: unmatched, byNameFrequency: ranked }, null, 2) + "\n"
);

const matched = lineups.reduce((n, l) => n + Object.keys(l.numbers).length, 0);
console.log(`wrote lineups.json — ${lineups.length} lineups, ${matched} matched numbers`);
console.log(`unmatched distinct names: ${ranked.length} (see unmatched-report.json)`);
if (ranked.length) {
  console.log("top unmatched (add to aliases.json):");
  for (const [name, n] of ranked.slice(0, 15)) console.log(`  ${n}×  ${name}`);
}
