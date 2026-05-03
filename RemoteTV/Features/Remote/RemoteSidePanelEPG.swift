import SwiftUI

/// EPG side panel: shows what's on Romanian TV right now, with drill-in for a full
/// per-channel daily schedule. Sits to the *right* of the remote (alongside the sniff
/// log) — left side is reserved for app launchers.
///
/// Two-state internal layout driven by `vm.selectedChannelID`:
///   * `nil` → search-able list of all 360+ channels with current programme inline.
///   * non-nil → today's schedule for that channel, with a Back button that clears the
///     selection.
@MainActor
struct RemoteSidePanelEPG: View {
    @Bindable var vm: EPGViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let error = vm.lastError {
                errorView(error)
            } else if vm.isLoading && vm.guide == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if vm.guide == nil {
                Text("Tap Refresh to load today's TV guide.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let _ = vm.selectedChannel {
                scheduleDetail
            } else {
                channelList
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RemoteTheme.body.opacity(0.5))
        .overlay(alignment: .leading) {
            // Hairline separator; mirrors the trailing hairline on the left-side panels.
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)
        }
        .colorScheme(.dark)
        .task {
            await vm.loadIfNeeded()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            if vm.selectedChannel != nil {
                Button {
                    vm.selectedChannelID = nil
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Back to channel list")
            }

            Text(vm.selectedChannel?.primaryName ?? "TV Guide")
                .font(.title3.bold())
                .lineLimit(1)
                .foregroundStyle(.white)

            Spacer()

            Button {
                Task { await vm.reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .disabled(vm.isLoading)
            .accessibilityLabel("Refresh TV guide")
        }
    }

    // MARK: - List mode

    @ViewBuilder
    private var channelList: some View {
        TextField("Search channels", text: $vm.searchText)
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

        let channels = vm.filteredChannels
        if channels.isEmpty {
            Text("No channels match \"\(vm.searchText)\".")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(channels) { channel in
                        Button {
                            vm.selectedChannelID = channel.id
                        } label: {
                            channelRow(channel)
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(accessibilityLabel(for: channel))
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func channelRow(_ channel: EPGChannel) -> some View {
        let now = vm.nowPlaying(for: channel.id)
        VStack(alignment: .leading, spacing: 2) {
            Text(channel.primaryName)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .lineLimit(1)
            if let now {
                Text(now.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("No data for now")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func accessibilityLabel(for channel: EPGChannel) -> String {
        if let now = vm.nowPlaying(for: channel.id) {
            "\(channel.primaryName), now playing \(now.title)"
        } else {
            "\(channel.primaryName), no current programme"
        }
    }

    // MARK: - Detail mode

    @ViewBuilder
    private var scheduleDetail: some View {
        Text(Date.now, format: .dateTime.weekday(.wide).day().month())
            .font(.caption)
            .foregroundStyle(.secondary)

        let programmes = vm.programmesForSelected
        if programmes.isEmpty {
            Text("No programmes in the feed for today.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(programmes) { programme in
                        programmeRow(programme)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func programmeRow(_ programme: EPGProgramme) -> some View {
        let isLive = programme.isLive()
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(programme.start, format: .dateTime.hour().minute())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isLive ? .white : .secondary)
                Text(programme.stop, format: .dateTime.hour().minute())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(programme.title)
                    .font(.caption.weight(isLive ? .bold : .regular))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let subtitle = programme.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isLive ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: programme, isLive: isLive))
    }

    private func accessibilityLabel(for programme: EPGProgramme, isLive: Bool) -> String {
        let prefix = isLive ? "Now playing: " : ""
        let times = "\(programme.start.formatted(date: .omitted, time: .shortened)) to \(programme.stop.formatted(date: .omitted, time: .shortened))"
        return "\(prefix)\(programme.title), \(times)"
    }

    // MARK: - Error

    @ViewBuilder
    private func errorView(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Couldn't load TV guide", systemImage: "exclamationmark.triangle")
                .font(.footnote.bold())
                .foregroundStyle(.orange)
            Text(error)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Button("Retry") {
                Task { await vm.reload() }
            }
            .buttonStyle(.bordered)
        }
    }
}
