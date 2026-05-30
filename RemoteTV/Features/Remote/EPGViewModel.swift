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

    /// The EPG channel id the user has pinned as "what's currently on the TV". Persisted
    /// across launches via `UserDefaults` so the pin survives backgrounding the app.
    ///
    /// Why manual rather than auto-detected: Samsung's Tizen WebSocket on this generation
    /// of TVs is silent on state changes (the project's `CLAUDE.md` notes this), and there
    /// is no documented Tizen REST endpoint for the current broadcast channel — SmartThings
    /// exposes it, but only via cloud OAuth. A manual pin is the highest-honesty option
    /// until we have an empirical WebSocket frame to parse from the sniff log.
    var pinnedChannelID: String? {
        didSet { Self.userDefaults.set(pinnedChannelID, forKey: Self.pinnedKey) }
    }

    private static let userDefaults: UserDefaults = .standard
    private static let pinnedKey = "pinnedTVChannelID"

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
        self.pinnedChannelID = Self.userDefaults.string(forKey: Self.pinnedKey)
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

    /// The pinned channel object, if any.
    var pinnedChannel: EPGChannel? {
        guard let id = pinnedChannelID else { return nil }
        return guide?.channels.first { $0.id == id }
    }

    /// What's airing on the pinned channel right now. Drives the "Now on TV" pill above
    /// the remote canvas.
    var pinnedNowPlaying: EPGProgramme? {
        guard let id = pinnedChannelID else { return nil }
        return guide?.nowPlaying(on: id)
    }

    /// `true` when the given channel id is the currently-pinned one.
    func isPinned(_ channelID: String) -> Bool {
        pinnedChannelID == channelID
    }

    /// Toggle pin for the given channel id.
    func togglePin(_ channelID: String) {
        pinnedChannelID = (pinnedChannelID == channelID) ? nil : channelID
    }

    // MARK: - Tune macro

    /// TV channel number for `channelID`, if we have one in ``KnownChannelNumbers``.
    /// Surfaced in the UI both as a small badge on the channel row and to gate the
    /// "Tune" button (we hide it when no number is known rather than fire a macro that
    /// would do the wrong thing).
    func tvChannelNumber(for channelID: String) -> Int? {
        KnownChannelNumbers.number(for: channelID)
    }

    /// `true` when we know the TV channel number for this id and can fire a tune macro.
    func canTune(_ channelID: String) -> Bool {
        tvChannelNumber(for: channelID) != nil
    }

    /// Builds the `[TVCommand]` sequence that tunes the TV to a known channel: each
    /// digit followed by `KEY_ENTER`. Returns nil if the channel isn't in the catalog
    /// (so callers can disable the Tune affordance instead of firing the wrong keys).
    ///
    /// Why include `KEY_ENTER`: most Tizen builds wait ~1.5 s after the last digit
    /// before tuning. The trailing Enter eliminates that delay so the channel
    /// switches immediately after the last digit lands.
    func tuneCommands(for channelID: String) -> [TVCommand]? {
        guard let number = tvChannelNumber(for: channelID) else { return nil }
        return Self.tuneCommands(for: number)
    }

    /// Pure helper exposed for tests — splits an integer into its decimal digits and
    /// maps each to the matching `KEY_<n>`, then appends `KEY_ENTER`.
    static func tuneCommands(for channelNumber: Int) -> [TVCommand] {
        let digits = String(channelNumber).compactMap { $0.wholeNumberValue }
        return digits.compactMap { TVCommand.digit($0) } + [.enter]
    }
}
