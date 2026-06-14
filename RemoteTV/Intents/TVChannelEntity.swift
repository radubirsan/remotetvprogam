import AppIntents

/// A tunable TV channel exposed to Siri / Shortcuts, backed by ``KnownChannelNumbers``.
/// Static by design: the lineup map is compiled in, so entity resolution needs no
/// network and works even when the TV is off.
struct TVChannelEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "TV Channel"
    static let defaultQuery = TVChannelQuery()

    /// EPG channel id (`Digi.24.HD.ro` style) — same key ``KnownChannelNumbers`` uses.
    let id: String
    let name: String
    let number: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "Channel \(number)")
    }

    /// The whole known lineup, ordered by channel number (the EPG list's order).
    static var all: [TVChannelEntity] {
        KnownChannelNumbers.orderedIDs.compactMap { id in
            guard let number = KnownChannelNumbers.number(for: id) else { return nil }
            return TVChannelEntity(
                id: id,
                name: KnownChannelNumbers.displayName(for: id),
                number: number
            )
        }
    }
}

struct TVChannelQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [TVChannelEntity] {
        TVChannelEntity.all.filter { identifiers.contains($0.id) }
    }

    /// Lets Siri resolve a spoken name ("tune to Digi 24") against the lineup.
    func entities(matching string: String) async throws -> [TVChannelEntity] {
        TVChannelEntity.all.filter { $0.name.localizedStandardContains(string) }
    }

    func suggestedEntities() async throws -> [TVChannelEntity] {
        // The full lineup is 100+ rows; suggest the head of the list (lowest channel
        // numbers — where the popular channels sit on this lineup) and let search
        // cover the tail.
        Array(TVChannelEntity.all.prefix(30))
    }
}
