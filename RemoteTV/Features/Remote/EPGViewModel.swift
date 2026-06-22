import Foundation
import RemoteTVCore
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

    /// Programmes grouped by channel id and sorted by start — rebuilt once each time a guide
    /// loads. The timeline grid reads this per row instead of re-filtering the full programme
    /// list (`EPGGuide.programmes(for:)` is O(all programmes)) on every render, which matters
    /// when ~150 rows each ask for their schedule.
    private(set) var programmesByChannel: [String: [EPGProgramme]] = [:]

    /// Two-way binding for the panel's `.searchable` field.
    var searchText: String = ""

    /// The category chip the user has selected in the redesigned guide. Default `.all`
    /// keeps the full lineup visible (and keeps `filteredChannels` byte-for-byte
    /// equivalent to the old search-only behaviour the unit tests assert).
    var selectedCategory: GuideCategory = .all

    /// Drives the channel-schedule navigation push: setting it (tapping a row or the
    /// featured card) pushes ``ChannelScheduleScreen`` for that id; the native back button
    /// / edge-swipe clears it back to `nil`. Bound via `navigationDestination(item:)`.
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

    /// Best-effort guess at the channel the TV is on *right now*, inferred from the tuning
    /// commands the remote itself sends (number-pad digits, the tune macro, channel ▲/▼ —
    /// fed in via `RemoteViewModel.onChannelEstimated`). Unlike ``pinnedChannelID`` this is
    /// **not** persisted and **not** ground truth: Tizen never reports channel state back, so
    /// the guess drifts the moment the channel is changed on the physical remote. It is
    /// superseded by an explicit pin and surfaced with a distinct "≈ auto" treatment in the
    /// pill (see ``nowOnTVIsEstimated``) so it never masquerades as confirmed.
    var estimatedChannelID: String?

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
            let loaded = try await client.loadGuide(forceRefresh: forceRefresh)
            guide = loaded
            programmesByChannel = Dictionary(grouping: loaded.programmes, by: \.channelID)
                .mapValues { $0.sorted { $0.start < $1.start } }
        } catch {
            lastError = String(describing: error)
        }
    }

    // MARK: - Derived data

    /// Channels shown in the guide: every entry in ``KnownChannelNumbers/mapping``,
    /// ordered by TV channel number (the order the mapping is written in). Channels the
    /// daily feed happens to omit are still listed — synthesized from the id with a
    /// humanized name and no programmes — so the list always mirrors the user's full
    /// tunable lineup rather than just what's in today's XMLTV dump. ``searchText``
    /// filters within that set (case- and diacritic-insensitive) without reordering.
    var filteredChannels: [EPGChannel] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let bySearch: [EPGChannel]
        if trimmed.isEmpty {
            bySearch = allKnownChannels
        } else {
            bySearch = allKnownChannels.filter { channel in
                channel.primaryName.localizedStandardContains(trimmed) ||
                channel.id.localizedStandardContains(trimmed) ||
                channel.displayNames.contains { $0.localizedStandardContains(trimmed) }
            }
        }
        guard selectedCategory != .all else { return bySearch }
        return bySearch.filter { selectedCategory.matches(nowPlaying(for: $0.id)) }
    }

    /// The user's full known lineup as ``EPGChannel`` values, ordered by channel
    /// number. Each id resolves to the feed's channel when today's dump includes it,
    /// or a synthesized placeholder when it doesn't.
    private var allKnownChannels: [EPGChannel] {
        KnownChannelNumbers.orderedIDs.compactMap(channel(for:))
    }

    /// Resolves an id to an ``EPGChannel``: the feed's entry if present (real
    /// display name + icon), otherwise a placeholder synthesized from the id for any
    /// id in ``KnownChannelNumbers/mapping``. Nil for ids we know nothing about.
    /// Public resolver for a single channel id (feed entry or synthesized placeholder).
    /// Used by the redesigned guide to render the featured card from a channel id.
    func channel(withID id: String) -> EPGChannel? { channel(for: id) }

    private func channel(for id: String) -> EPGChannel? {
        if let inFeed = guide?.channels.first(where: { $0.id == id }) { return inFeed }
        guard KnownChannelNumbers.number(for: id) != nil else { return nil }
        return EPGChannel(id: id, displayNames: [KnownChannelNumbers.displayName(for: id)], iconURL: nil)
    }

    /// What's airing right now on `channelID`, if anything in the feed overlaps `Date.now`.
    /// Inline in the channel-list rows so the user sees the current show without drilling in.
    func nowPlaying(for channelID: String, at date: Date = .now) -> EPGProgramme? {
        guide?.nowPlaying(on: channelID, at: date)
    }

    /// The next programme to air on `channelID` after `date` — first entry in today's
    /// schedule whose start is in the future. Drives the redesigned row's "Next:" line.
    func nextProgramme(for channelID: String, after date: Date = .now) -> EPGProgramme? {
        guide?.programmes(for: channelID)
            .first { $0.start > date }
    }

    /// Fraction (0...1) of the way through `programme` at `date`. Drives the row and
    /// featured-card progress bars; clamped so a just-started or already-finished show
    /// never overflows the track.
    func progress(of programme: EPGProgramme, at date: Date = .now) -> Double {
        let total = programme.duration
        guard total > 0 else { return 0 }
        let elapsed = date.timeIntervalSince(programme.start)
        return min(max(elapsed / total, 0), 1)
    }

    /// The channel to surface in the featured "Live Now" card: the pinned channel when
    /// it's actually airing something, otherwise the first channel in the visible list
    /// with a current programme. Returns `nil` when nothing is airing (feed not loaded
    /// or no overlap), and the view hides the card.
    func featuredChannelID(at date: Date = .now) -> String? {
        if let pinned = pinnedChannelID, nowPlaying(for: pinned, at: date) != nil {
            return pinned
        }
        return filteredChannels.first { nowPlaying(for: $0.id, at: date) != nil }?.id
    }

    /// Today's schedule for `channelID`, sorted by start time. Drives the pushed
    /// ``ChannelScheduleScreen`` — decoupled from `selectedChannelID` so the screen reads
    /// straight from the id the navigation push handed it.
    func programmes(forChannel channelID: String, on day: Date = .now) -> [EPGProgramme] {
        guide?.programmes(for: channelID, on: day) ?? []
    }

    /// The pinned channel object, if any.
    var pinnedChannel: EPGChannel? {
        pinnedChannelID.flatMap(channel(for:))
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

    // MARK: - Estimated channel (best-effort, from the remote's own tuning)

    /// Records the channel *number* the remote believes it just tuned to, mapping it back to
    /// an EPG id for the "Now on TV" pill. A number outside the known lineup clears the
    /// estimate — we'd rather show nothing than the wrong channel. Kicks a guide load when one
    /// hasn't happened yet so the pill can fill in the live programme.
    func noteTunedChannel(_ number: Int) {
        estimatedChannelID = KnownChannelNumbers.channelID(forNumber: number)
        if estimatedChannelID != nil, guide == nil {
            Task { await loadIfNeeded() }
        }
    }

    /// The channel to surface in the "Now on TV" pill: an explicit user pin wins; otherwise
    /// the best-effort estimate inferred from the remote's own tuning. Nil when neither exists.
    var nowOnTVChannelID: String? { pinnedChannelID ?? estimatedChannelID }

    /// The resolved channel object for ``nowOnTVChannelID``.
    var nowOnTVChannel: EPGChannel? { nowOnTVChannelID.flatMap(channel(for:)) }

    /// What's airing on ``nowOnTVChannelID`` right now, if the feed overlaps `Date.now`.
    var nowOnTVNowPlaying: EPGProgramme? {
        guard let id = nowOnTVChannelID else { return nil }
        return guide?.nowPlaying(on: id)
    }

    /// True when the pill is showing the inferred estimate rather than a user-confirmed pin —
    /// drives the distinct "≈ auto" styling so the guess never looks authoritative.
    var nowOnTVIsEstimated: Bool { pinnedChannelID == nil && estimatedChannelID != nil }

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

/// The category-filter chips shown above the guide's channel list (mirrors the design
/// handoff: All · Live · Movies · Sports · News · Kids).
///
/// Matching is best-effort against the XMLTV `categories` of whatever's airing now —
/// the upstream Romanian feed tags shows in Romanian, so each case carries both English
/// and Romanian keywords and folds away case/diacritics before comparing. `.all` short-
/// circuits to "everything" and `.live` means "currently airing anything".
enum GuideCategory: String, CaseIterable, Identifiable {
    case all, live, movies, sports, news, kids

    var id: String { rawValue }

    /// Chip label.
    var title: String {
        switch self {
        case .all: "All"
        case .live: "Live"
        case .movies: "Movies"
        case .sports: "Sports"
        case .news: "News"
        case .kids: "Kids"
        }
    }

    /// Lowercased, diacritic-free substrings that mark a programme as belonging to this
    /// category. Empty for `.all`/`.live` (handled specially in ``matches(_:)``).
    private var keywords: [String] {
        switch self {
        case .all, .live: []
        case .movies: ["film", "movie", "cinema"]
        case .sports: ["sport", "fotbal", "soccer", "tenis", "tennis", "match", "meci"]
        case .news: ["news", "stiri", "stire", "actualit", "jurnal"]
        case .kids: ["kids", "copii", "desene", "children", "cartoon", "animat", "junior"]
        }
    }

    /// Whether a channel showing `programme` right now belongs to this category.
    /// `.all` always matches; `.live` matches any channel that has a current programme.
    func matches(_ programme: EPGProgramme?) -> Bool {
        switch self {
        case .all:
            return true
        case .live:
            return programme != nil
        default:
            guard let programme else { return false }
            let haystack = (programme.categories.joined(separator: " ") + " " + programme.title)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return keywords.contains { haystack.contains($0) }
        }
    }
}
