import SwiftUI

/// Compact horizontal strip floated above the remote canvas.
///
/// Three states:
///   * **Pinned channel** (`channel != nil`, `isEstimated == false`) — a user-confirmed pin;
///     channel name + live programme + when it ends, in confident yellow. Tap opens its
///     schedule.
///   * **Estimated channel** (`channel != nil`, `isEstimated == true`) — a best-effort guess
///     inferred from the remote's own tuning, rendered with a distinct "≈ auto" treatment so
///     it never looks confirmed (the TV never reports its channel back, so this can drift).
///   * **Prompt** (`channel == nil`) — a "Check out TV Guide" call-to-action; tap opens the
///     main guide.
///
/// Why the channel isn't truly synced: this generation of Tizen is silent on broadcast state
/// changes over the WebSocket and Samsung doesn't expose a current-channel REST endpoint
/// outside the SmartThings cloud. See `EPGViewModel` `estimatedChannelID` / `pinnedChannelID`.
@MainActor
struct NowOnTVPill: View {
    /// The channel to show (pinned or estimated), or `nil` for the "Check out TV Guide" prompt.
    let channel: EPGChannel?
    let programme: EPGProgramme?
    /// When true, `channel` is the best-effort estimate (not a user pin) — render the "≈ auto"
    /// treatment so the guess never masquerades as confirmed.
    var isEstimated: Bool = true
    let onTap: () -> Void

    /// Tint for the leading icon + border: yellow for a user-pinned channel, app accent for
    /// the estimate and the discovery prompt (both are "soft" states).
    private var accent: Color { (channel != nil && !isEstimated) ? .yellow : RemoteTheme.accent }

    /// Leading glyph: pin for a confirmed pin, antenna for the estimate, sparkles for the prompt.
    private var leadingIcon: String {
        guard channel != nil else { return "sparkles.tv" }
        return isEstimated ? "antenna.radiowaves.left.and.right" : "pin.fill"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: leadingIcon)
                    .font(.caption2)
                    .foregroundStyle(accent)

                VStack(alignment: .leading, spacing: 1) {
                    if let channel {
                        HStack(spacing: 4) {
                            Text(channel.primaryName)
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if programme != nil {
                                Text(isEstimated ? "≈ now" : "· now")
                                    .font(.caption2)
                                    .foregroundStyle(isEstimated ? accent : .secondary)
                            }
                        }
                        if let programme {
                            HStack(spacing: 4) {
                                Text(programme.title)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1)
                                Text("until")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(programme.stop, format: .dateTime.hour().minute())
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("No programme data right now")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    } else {
                        Text("Check out TV Guide")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("See what's on now and next")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.black.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(accent.opacity(0.35), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 12)
            .padding(.top, 2)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(channel == nil ? "Opens the TV guide." : "Opens the TV guide for this channel.")
    }

    private var accessibilityLabel: String {
        guard let channel else { return "Check out TV Guide. See what's on now and next." }
        let prefix = isEstimated ? "Estimated channel" : "Now on TV"
        if let programme {
            let until = programme.stop.formatted(date: .omitted, time: .shortened)
            return "\(prefix): \(channel.primaryName), \(programme.title), until \(until)"
        }
        return "\(prefix): \(channel.primaryName), no programme data"
    }
}
