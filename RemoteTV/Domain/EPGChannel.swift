import Foundation

/// A TV channel as published in the daily EPG JSON dump.
///
/// Mirrors the on-the-wire shape produced by the `tvepg dump` CLI in `TVScheduel/`,
/// which is what `.github/workflows/epg-update.yml` commits to the `epg-data` branch.
struct EPGChannel: Codable, Sendable, Hashable, Identifiable {
    /// XMLTV channel id, e.g. `Digi.24.HD.ro`. Stable across regenerations.
    let id: String
    /// All `<display-name>` entries from the source. Often just one.
    let displayNames: [String]
    let iconURL: URL?

    /// First display name, falling back to the id if the source omitted them.
    var primaryName: String { displayNames.first ?? id }
}
