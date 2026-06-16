import RemoteTVCore
import SwiftUI

/// Small coloured dot that replaces the design's static "MIC" indicator. Acts as the
/// app's compact connection-state surface: grey when disconnected, amber while
/// connecting, blue while waiting for the user to accept on the TV, green once
/// authenticated, red when the latest action errored. Pulses while transitioning so
/// the user can spot progress at a glance without a separate status pill.
@MainActor
struct RemoteStatusLED: View {
    let state: TVConnectionState
    /// Last-known TV power state. Used to render `.connected + .off` as a dim grey
    /// (TV is reachable but in standby) versus the solid green of a fully active TV.
    /// `.unknown` is treated as "assume on" so the LED doesn't flicker grey during the
    /// brief window between WS connect and the first successful REST poll.
    let powerState: TVPowerState
    /// Non-nil means the most recent connect/send/launch surfaced an error — the LED
    /// turns red regardless of `state`.
    let hasError: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !shouldPulse)) { context in
            let phase = pulsePhase(at: context.date)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .opacity(shouldPulse ? 0.45 + phase * 0.55 : 1.0)
                .shadow(color: color.opacity(0.7), radius: 4)
        }
    }

    private var shouldPulse: Bool {
        if hasError { return false }
        switch state {
        case .connecting, .awaitingPairing: return true
        default: return false
        }
    }

    private var color: Color {
        if hasError { return .red }
        switch state {
        case .disconnected:    return Color(white: 0.35)
        case .connecting:      return .orange
        case .awaitingPairing: return .blue
        case .connected:       return powerState == .off ? Color(white: 0.55) : .green
        case .failed:          return .red
        }
    }

    /// Maps wall-clock time to a 0...1 phase via a 1.6s cosine cycle. Using the timeline's
    /// own date keeps the animation stable across re-renders without storing `@State`.
    private func pulsePhase(at date: Date) -> Double {
        let cycleSeconds = 1.6
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycleSeconds)
        let normalized = t / cycleSeconds
        return (1 - cos(2 * .pi * normalized)) / 2
    }
}
