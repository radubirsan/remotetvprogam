import Foundation
import SwiftUI

/// Drives the ``RemoteSidePanelEPG`` side panel.
///
/// Owns one ``EPGClient`` for the lifetime of the screen so the in-memory cache survives
/// repeated panel toggles. Holds:
///   * the loaded ``EPGGuide`` (or `nil` while loading / on error)
///   * search text the user types in the panel's search field
///   * the optional `selectedChannelID` that drives the list/detail toggle inside the panel
///
/// State changes are observed by SwiftUI through `@Observable`. The class is `@MainActor`
/// because the panel reads its properties directly from the view body — per the project's
/// convention since there's no main-actor default isolation in this target.
@MainActor
@Observable
final class EPGViewModel {

    // MARK: - State

    private(set) var guide: EPGGuide?
    private(set) var isLoading: Bool = false
    private(set) var lastError: String?

    /// Two-way binding for the panel's `.searchable` field.
    var searchText: String = ""

    /// `nil` → panel shows the channel list. Non-nil → panel shows today's schedule
    /// for the selected channel id with a Back button to clear the selection.
    var selectedChannelID: String?

    // MARK: - Init

    /// `EPGClient` is held privately so the panel can't bypass the view-model and call
    /// it directly. Default config points at the `epg-data` branch of this project's
    /// GitHub repo.
    private let client: EPGClient

    init(
        client: EPGClient = EPGClient(
            configuration: .init(sourceURL: EPGClient.Configuration.defaultSourceURL)
        )
    ) {
        self.client = client
    }

    // MARK: - Loading

    /// First-time load. Idempotent — safe to call from `.task`/`.onAppear` repeatedly;
    /// `EPGClient`'s in-memory cache returns instantly after the first call.
    func loadIfNeeded() async {
        guard guide == nil, !isLoading else { return }
        await reload(forceRefresh: false)
    }

    /// Force a network refetch (bypasses both in-memory and on-disk caches).
    func reload(forceRefresh: Bool = true) async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            guide = try await client.loadGuide(forceRefresh: forceRefresh)
        } catch {
            lastError = String(describing: error)
        }
    }

    // MARK: - Derived data

    /// Channels filtered by ``searchText`` (case- and diacritic-insensitive),
    /// alphabetised by display name.
    var filteredChannels: [EPGChannel] {
        guard let channels = guide?.channels else { return [] }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [EPGChannel]
        if trimmed.isEmpty {
            base = channels
        } else {
            base = channels.filter { channel in
                channel.primaryName.localizedStandardContains(trimmed) ||
                channel.id.localizedStandardContains(trimmed) ||
                channel.displayNames.contains { $0.localizedStandardContains(trimmed) }
            }
        }
        return base.sorted {
            $0.primaryName.localizedStandardCompare($1.primaryName) == .orderedAscending
        }
    }

    /// What's airing right now on `channelID`, if anything in the feed overlaps `Date.now`.
    /// Inline in the channel-list rows so the user sees the current show without drilling in.
    func nowPlaying(for channelID: String, at date: Date = .now) -> EPGProgramme? {
        guide?.nowPlaying(on: channelID, at: date)
    }

    /// Today's schedule for the currently selected channel, sorted by start time.
    var programmesForSelected: [EPGProgramme] {
        guard let id = selectedChannelID else { return [] }
        return guide?.programmes(for: id, on: .now) ?? []
    }

    /// The selected channel object (display name, etc.) for the detail header.
    var selectedChannel: EPGChannel? {
        guard let id = selectedChannelID else { return nil }
        return guide?.channels.first { $0.id == id }
    }
}
