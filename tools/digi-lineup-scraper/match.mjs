// Matches a scraped Digi channel display-name to our XMLTV channel id (e.g. "Digi 24 HD"
// -> "Digi.24.HD.ro"). Names never align perfectly across sources, so matching is:
//   1) exact match on a normalized id-derived name,
//   2) an `aliases.json` override (for rebrands like "Pro Arena" -> PRO.X.ro),
// and anything still unmatched is reported for manual review (extend aliases.json).

import { readFile } from "node:fs/promises";

/** Lowercase, strip diacritics, drop punctuation, collapse whitespace. HD/SD are KEPT —
 *  they distinguish separate channel ids with separate numbers. */
export function normalize(s) {
  return s
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "") // diacritics
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ");
}

/** Human name derived from an id: drop a trailing 2-letter country code, dots -> spaces.
 *  Mirrors KnownChannelNumbers.displayName(for:) in the Swift app. */
export function nameFromID(id) {
  const parts = id.split(".");
  if (parts.length && /^[a-z]{2}$/.test(parts[parts.length - 1])) parts.pop();
  return parts.join(" ");
}

export async function buildMatcher() {
  // Canonical id universe = the union of ids across the seed lineups.json.
  const seed = JSON.parse(
    await readFile(new URL("../../RemoteTV/Resources/lineups.json", import.meta.url))
  );
  const ids = new Set();
  for (const l of seed.lineups) for (const id of Object.keys(l.numbers)) ids.add(id);

  const aliases = JSON.parse(await readFile(new URL("./aliases.json", import.meta.url)));

  // normalized name -> id
  const index = new Map();
  for (const id of ids) index.set(normalize(nameFromID(id)), id);
  for (const [name, id] of Object.entries(aliases)) index.set(normalize(name), id);

  return {
    ids,
    /** Returns the matched id, or null. */
    match(scrapedName) {
      return index.get(normalize(scrapedName)) ?? null;
    },
  };
}
