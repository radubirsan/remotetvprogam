import AppIntents
import RemoteTVCore

/// A launchable Tizen app exposed to Siri / Shortcuts. Combines the dedicated shortcut
/// apps (``TVApp``) with the probe catalog (``KnownTVApps``), deduped. Static by design —
/// no probe round-trip at resolution time; if the app isn't installed on the TV, the
/// launch itself reports the failure.
struct TVAppEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "TV App"
    static let defaultQuery = TVAppQuery()

    /// Tizen app ID, e.g. `111299001912` (YouTube).
    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    /// Dedicated shortcuts first (their names are canonical), then the catalog.
    /// Deduped by ID *and* name — the catalog intentionally probes duplicate IDs and
    /// rebrand variants (HBO Go/Max), which would read as clutter in a Shortcuts picker.
    static var all: [TVAppEntity] {
        let dedicated = TVApp.allCases.map { TVAppEntity(id: $0.appID, name: $0.displayName) }
        let catalog = KnownTVApps.catalog.map { TVAppEntity(id: $0.appID, name: $0.fallbackName) }
        var seenIDs: Set<String> = []
        var seenNames: Set<String> = []
        return (dedicated + catalog).filter { entity in
            seenIDs.insert(entity.id).inserted && seenNames.insert(entity.name.lowercased()).inserted
        }
    }
}

struct TVAppQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [TVAppEntity] {
        TVAppEntity.all.filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [TVAppEntity] {
        TVAppEntity.all.filter { $0.name.localizedStandardContains(string) }
    }

    func suggestedEntities() async throws -> [TVAppEntity] {
        TVAppEntity.all
    }
}
