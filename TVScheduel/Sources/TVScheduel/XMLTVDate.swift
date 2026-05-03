import Foundation

/// Parses XMLTV's compact date format.
///
/// XMLTV timestamps look like `20260503060000 +0200` — no separators, optional timezone.
/// Variants we accept (per the XMLTV DTD):
///   * `YYYYMMDDhhmmss ±ZZZZ`   (most common)
///   * `YYYYMMDDhhmmss`          (treated as UTC)
///   * `YYYYMMDDhhmm`            (seconds defaulted to 0)
///   * `YYYYMMDDhh`              (minutes/seconds defaulted to 0)
///
/// `Date.ParseStrategy` doesn't speak this dialect natively, so we hand-roll it.
enum XMLTVDate {

    static func parse(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Split on the space that separates timestamp from timezone (if any).
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let stamp = String(parts[0])
        let tzString = parts.count > 1 ? String(parts[1]) : nil

        // Pull out the digits we need from the stamp.
        guard stamp.count >= 10, stamp.allSatisfy(\.isNumber) else { return nil }

        let digits = Array(stamp)

        func intRange(_ lower: Int, _ upper: Int) -> Int? {
            guard upper <= digits.count else { return nil }
            return Int(String(digits[lower..<upper]))
        }

        guard let year = intRange(0, 4),
              let month = intRange(4, 6),
              let day = intRange(6, 8),
              let hour = intRange(8, 10) else {
            return nil
        }
        let minute = intRange(10, 12) ?? 0
        let second = intRange(12, 14) ?? 0

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = parseTimeZone(tzString) ?? .gmt

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = components.timeZone ?? .gmt
        return calendar.date(from: components)
    }

    /// Parses `+0200` / `-0530` / `Z` / `UTC` style suffixes.
    private static func parseTimeZone(_ raw: String?) -> TimeZone? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw == "Z" || raw.uppercased() == "UTC" { return .gmt }
        guard raw.count == 5 else { return TimeZone(identifier: raw) }

        let sign: Int
        switch raw.first {
        case "+": sign = 1
        case "-": sign = -1
        default: return nil
        }
        let body = raw.dropFirst()
        guard body.count == 4,
              let hours = Int(body.prefix(2)),
              let minutes = Int(body.suffix(2)) else {
            return nil
        }
        return TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60))
    }
}
