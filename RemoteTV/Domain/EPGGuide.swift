import Foundation

/// A complete decoded EPG dump — channels, programmes, and the timestamp of the
/// upstream conversion (set by the GitHub Actions workflow, not by the client).
struct EPGGuide: Codable, Sendable {
    let channels: [EPGChannel]
    let programmes: [EPGProgramme]
    let fetchedAt: Date

    /// Programmes for one channel, sorted by start time.
    func programmes(for channelID: String) -> [EPGProgramme] {
        programmes
            .filter { $0.channelID == channelID }
            .sorted { $0.start < $1.start }
    }

    /// Programmes for one channel that overlap a given calendar day in the user's
    /// current timezone.
    func programmes(
        for channelID: String,
        on day: Date,
        calendar: Calendar = .current
    ) -> [EPGProgramme] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return programmes(for: channelID).filter { $0.start < dayEnd && $0.stop > dayStart }
    }

    /// What's airing on the channel at `date`, if anything in the feed overlaps.
    func nowPlaying(on channelID: String, at date: Date = .now) -> EPGProgramme? {
        programmes.first { $0.channelID == channelID && $0.isLive(at: date) }
    }
}
