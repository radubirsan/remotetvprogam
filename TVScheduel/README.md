# TVScheduel

Romanian XMLTV grabber for the RemoteTV project. Fetches an XMLTV feed (default: the
[`iptv-org/epg`](https://github.com/iptv-org/epg) Romanian guide), caches it for 24h on
disk, parses channels and programmes, and exposes them as Swift models or as JSON.

## What is XMLTV?

[XMLTV](https://github.com/xmltv/xmltv) is a long-running community format for TV
programme listings. A document is a flat list of `<channel>` definitions and
`<programme>` entries with start/stop times. Most public Romanian guides — including
ones generated for Digi channels — publish in this format.

## Build & run

```sh
cd TVScheduel
swift run tvepg --help
swift run tvepg channels
swift run tvepg today "Digi 24"
swift run tvepg dump > ro-guide.json
```

The first run downloads the guide (a few MB to a few tens of MB depending on how many
days are included). Subsequent runs within 24h read from the on-disk cache at
`/tmp/tvepg-cache/`. Pass `--refresh` to force a re-download.

## Picking a source

The default URL is:

```
https://epgshare01.online/epgshare01/epg_ripper_RO1.xml.gz
```

This is a daily-regenerated Romanian XMLTV cut hosted by epgshare01. It covers
~360 channels — every Digi service (Digi 24, Digi Sport 1–4, Digi Animal World,
Digi Life, Digi World, Digi 4K), Pro TV, Antena 1/3, Antena Stars, TVR, AXN, AMC,
Animal Planet, Acasa, Kanal D, Prima TV, and a long tail of cable channels. Ships
gzipped (~13 MB on the wire).

Override with `--source` or `TVEPG_SOURCE_URL`:

```sh
TVEPG_SOURCE_URL=https://epgshare01.online/epgshare01/epg_ripper_RO1.xml.gz \
  swift run tvepg today "Pro TV"
```

Other community Romanian sources worth knowing about (community feeds come and go,
so check before relying on any of them):

- `epgshare01.online` — per-country `epg_ripper_*.xml.gz` cuts, regenerated daily.
- `iptv-org/epg` — runnable Node.js grabber; you host the output yourself.
- `open-epg.com` — `https://www.open-epg.com/files/romania1.xml` (no gzip, ~3.5 MB).
- `i.mjh.nz` — global aggregate with all channels in one file (no Romania-only cut).

## Embedding in the iOS app

The package exposes `TVScheduel` as a library target. To pull it into the RemoteTV
Xcode project, add it as a local Swift package:

1. In Xcode: **File → Add Package Dependencies… → Add Local…** and select the
   `TVScheduel/` folder.
2. Add the `TVScheduel` library to the RemoteTV app target.
3. From SwiftUI:

   ```swift
   import TVScheduel

   let fetcher = XMLTVFetcher(
       configuration: .init(
           sourceURL: URL(string: "https://iptv-org.github.io/epg/guides/ro.xml")!,
           cacheDirectory: URL.cachesDirectory.appending(path: "tvepg")
       )
   )
   let guide = try await fetcher.fetchGuide()
   ```

   `Channel` and `Programme` are `Sendable`, `Codable`, and `Identifiable`, so they drop
   straight into a `List` or `ForEach`.

## Tests

```sh
swift test
```

Covers the date parser (timezone offsets, missing seconds, garbage input) and the
XMLTV parser (full document, malformed programmes, sorted output).
