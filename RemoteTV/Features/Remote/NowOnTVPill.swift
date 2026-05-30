import SwiftUI

/// Compact horizontal strip rendered above the remote canvas when the user has pinned
/// an EPG channel as "what's currently on the TV".
///
/// Shows the channel name, the live programme title, and the time the programme ends
/// — enough at-a-glance info to know whether to keep watching or change channel,
/// without opening the TV Guide panel. Tapping the pill jumps to that channel's full
/// schedule in the side panel (caller-provided callback).
///
/// Why this exists as a manual pin rather than auto-detected: this generation of Tizen
/// is silent on broadcast state changes over the WebSocket and Samsung doesn't expose
/// a current-channel REST endpoint outside the SmartThings cloud. See `EPGViewModel`
/// `pinnedChannelID` for the full reasoning.
@MainActor
struct NowOnTVPill: View {
    let channel: EPGChannel
    let programme: EPGProgramme?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)

                VStack(alignment: .leading, spacing: 1) {
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.black.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.yellow.opacity(0.35), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens the TV guide for this channel.")
    }

    private var accessibilityLabel: String {
        if let programme {
            let until = programme.stop.formatted(date: .omitted, time: .shortened)
            return "Now on TV: \(channel.primaryName), \(programme.title), until \(until)"
        }
        return "Now on TV: \(channel.primaryName), no programme data"
    }
}
