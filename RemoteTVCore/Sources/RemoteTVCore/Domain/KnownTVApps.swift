import Foundation

/// Curated list of Tizen app IDs we probe via `GET /api/v2/applications/<id>` to build the
/// "Installed Apps" list.
///
/// Samsung's `ed.installedApp.get` WebSocket event silently no-ops on recent Tizen builds,
/// so instead of true discovery we ask the TV whether each well-known ID resolves. A 200
/// means installed; anything else (404, timeout) means missing. Names are overwritten with
/// whatever the TV reports, so a wrong ``fallbackName`` here doesn't show in the UI — it's
/// only used if the response body lacks a `name`.
///
/// Netflix, Disney+, and YouTube are intentionally excluded: they already have dedicated
/// buttons in ``AppsSection``, and including them here would double them up.
///
/// This list is best-effort. IDs vary slightly between model years / regions; extras are
/// cheap (they just probe and filter out), missing entries just don't appear. Add more
/// over time.
public enum KnownTVApps {
    public struct Probe: Sendable {
        public let appID: String
        public let fallbackName: String

        public init(appID: String, fallbackName: String) {
            self.appID = appID
            self.fallbackName = fallbackName
        }
    }

    public static let catalog: [Probe] = [
        Probe(appID: "3201910019365", fallbackName: "Prime Video"),
        Probe(appID: "3201807016597", fallbackName: "Apple TV"),
        Probe(appID: "3201606009684", fallbackName: "Spotify"),
        Probe(appID: "3201606009684", fallbackName: "Spotify"),
        Probe(appID: "3201512006963", fallbackName: "Plex"),
        Probe(appID: "3201601007625", fallbackName: "Hulu"),
        // HBO has rebranded across HBO Go → HBO Max → Max → HBO Max again, each time
        // minting a new Tizen app ID. Probe all variants; dedupe-by-name in
        // ``SamsungTVService.requestInstalledApps`` collapses any that both resolve.
        Probe(appID: "3202301029760", fallbackName: "Max"),
        Probe(appID: "3201601007230", fallbackName: "HBO Max"),
        Probe(appID: "3201706012478", fallbackName: "HBO Go"),
        Probe(appID: "3202203023371", fallbackName: "Twitch"),
        Probe(appID: "3201910019457", fallbackName: "Paramount+"),
        Probe(appID: "3201911019187", fallbackName: "Peacock"),
        Probe(appID: "3201710014981", fallbackName: "Crunchyroll"),
        Probe(appID: "3201808016390", fallbackName: "Pluto TV"),
        Probe(appID: "3201707014031", fallbackName: "Tubi"),
        Probe(appID: "121299000612", fallbackName: "Deezer"),
        Probe(appID: "3202003020365", fallbackName: "Discovery+"),
        Probe(appID: "111477001034", fallbackName: "VUDU"),
        Probe(appID: "3201907018784", fallbackName: "Internet"),
        Probe(appID: "3201702011851", fallbackName: "Steam Link"),
        Probe(appID: "3201908018968", fallbackName: "Rakuten TV"),
        Probe(appID: "3201611010983", fallbackName: "YouTube Kids"),
        Probe(appID: "3201605008204", fallbackName: "Apple Music"),
    ]
}
