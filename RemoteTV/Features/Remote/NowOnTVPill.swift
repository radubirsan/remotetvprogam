import SwiftUI

/// Compact horizontal strip floated above the remote canvas.
///
/// Two states:
///   * **Pinned channel** (`channel != nil`) — shows the channel name, the live programme
///     title, and when it ends; tapping opens that channel's schedule in the TV Guide.
///   * **Prompt** (`channel == nil`) — shows a "Check out TV Guide" call-to-action;
///     tapping opens the main guide.
///
/// Why the pin is manual rather than auto-detected: this generation of Tizen is silent on
/// broadcast state changes over the WebSocket and Samsung doesn't expose a current-channel
/// REST endpoint outside the SmartThings cloud. See `EPGViewModel` `pinnedChannelID`.
@MainActor
struct NowOnTVPill: View {
    /// The pinned channel, or `nil` to show the "Check out TV Guide" prompt.
    let channel: EPGChannel?
    let programme: EPGProgramme?
    let onTap: () -> Void

    /// Tint for the leading icon + border: yellow for a pinned channel, app accent for
    /// the discovery prompt.
    private var accent: Color { channel == nil ? RemoteTheme.accent : .yellow }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: channel == nil ? "sparkles.tv" : "pin.fill")
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
                                Text("· now")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
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
        if let programme {
            let until = programme.stop.formatted(date: .omitted, time: .shortened)
            return "Now on TV: \(channel.primaryName), \(programme.title), until \(until)"
        }
        return "Now on TV: \(channel.primaryName), no programme data"
    }
}
