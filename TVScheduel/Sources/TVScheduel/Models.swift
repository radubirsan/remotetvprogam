import Foundation

/// A TV channel listed in an XMLTV feed.
public struct Channel: Codable, Sendable, Hashable, Identifiable {
    /// XMLTV `channel/@id` — the stable identifier used to link programmes to channels.
    public let id: String
    /// Human-readable names. XMLTV lets a channel publish multiple `<display-name>` entries
    /// (sometimes per-language); we keep them all.
    public let displayNames: [String]
    /// `<icon src="...">` if present.
    public let iconURL: URL?

    public init(id: String, displayNames: [String], iconURL: URL? = nil) {
        self.id = id
        self.displayNames = displayNames
        self.iconURL = iconURL
    }

    /// First display name, or the channel id if none was provided.
    public var primaryName: String { displayNames.first ?? id }
}

/// A scheduled programme on a channel.
public struct Programme: Codable, Sendable, Hashable, Identifiable {
    /// Synthetic id — `<channel>|<startEpoch>` — useful when surfacing in SwiftUI lists.
    public var id: String { "\(channelID)|\(Int(start.timeIntervalSince1970))" }

    public let channelID: String
    public let title: String
    public let subtitle: String?
    public let description: String?
    public let start: Date
    public let stop: Date
    public let categories: [String]

    public init(
        channelID: String,
        title: String,
        subtitle: String? = nil,
        description: String? = nil,
        start: Date,
        stop: Date,
        categories: [String] = []
    ) {
        self.channelID = channelID
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.start = start
        self.stop = stop
        self.categories = categories
    }
}

/// A complete decoded XMLTV guide.
public struct Guide: Codable, Sendable {
    public let channels: [Channel]
    public let programmes: [Programme]
    public let fetchedAt: Date

    public init(channels: [Channel], programmes: [Programme], fetchedAt: Date = .now) {
        self.channels = channels
        self.programmes = programmes
        self.fetchedAt = fetchedAt
    }

    /// Programmes for a given channel id, sorted by start time.
    public func programmes(for channelID: String) -> [Programme] {
        programmes
            .filter { $0.channelID == channelID }
            .sorted { $0.start < $1.start }
    }
}
