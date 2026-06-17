import RemoteTVCore
import SwiftUI

/// EPG screen: shows what's on Romanian TV right now, with drill-in for a full per-channel
/// daily schedule. Pushed as its own screen from ``RemoteView``'s TV Guide toolbar button
/// (it fills its frame; the navigation bar supplies the title and back button).
///
/// Two-state internal layout driven by `vm.selectedChannelID`:
///   * `nil` → search-able list of all 360+ channels with current programme inline.
///   * non-nil → today's schedule for that channel, with a Back button that clears the
///     selection.
@MainActor
struct RemoteSidePanelEPG: View {
    @Bindable var vm: EPGViewModel
    /// Dispatches a sequence of TV commands. Supplied by `RemoteView` so the panel can
    /// fire the Tune-to-channel macro through the same `RemoteViewModel.send` path the
    /// rest of the remote uses. Each command is awaited in order so the TV sees them
    /// as a clean digit-by-digit sequence rather than racing batch.
    let onDispatchMacro: ([TVCommand]) async -> Void

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
        .colorScheme(.dark)
        .task {
            await vm.loadIfNeeded()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            if let selected = vm.selectedChannel {
                // No in-panel back button here — the nav bar's single context-aware back
                // (in `RemoteView`) handles "schedule → channel list → leave guide".
                Text(selected.primaryName)
                    .font(.title3.bold())
                    .lineLimit(1)
                    .foregroundStyle(.white)

                Spacer()

                if let number = vm.tvChannelNumber(for: selected.id) {
                    Button {
                        Task {
                            // Fire the digit sequence then pin so the "Now on TV"
                            // pill matches what we just told the TV to tune to.
                            if let commands = vm.tuneCommands(for: selected.id) {
                                await onDispatchMacro(commands)
                            }
                            vm.pinnedChannelID = selected.id
                        }
                    } label: {
                        Label("Tune \(number)", systemImage: "tv.badge.wifi")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Tune the TV to channel \(number), \(selected.primaryName)")
                }

                Button {
                    vm.togglePin(selected.id)
                } label: {
                    Image(systemName: vm.isPinned(selected.id) ? "pin.fill" : "pin")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
                .tint(vm.isPinned(selected.id) ? .yellow : .accentColor)
                .accessibilityLabel(
                    vm.isPinned(selected.id)
                        ? "Unpin from remote"
                        : "Pin as TV's current channel"
                )
            } else {
                // List mode: the navigation bar supplies the "TV Guide" title, so the header
                // just holds the trailing Refresh control.
                Spacer()
            }

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
                        .contextMenu {
                            if let number = vm.tvChannelNumber(for: channel.id) {
                                Button(
                                    "Tune to channel \(number)",
                                    systemImage: "tv.badge.wifi"
                                ) {
                                    Task {
                                        if let commands = vm.tuneCommands(for: channel.id) {
                                            await onDispatchMacro(commands)
                                        }
                                        vm.pinnedChannelID = channel.id
                                    }
                                }
                            }
                            Button(
                                vm.isPinned(channel.id)
                                    ? "Unpin from remote"
                                    : "Pin as TV's current channel",
                                systemImage: vm.isPinned(channel.id) ? "pin.slash" : "pin"
                            ) {
                                vm.togglePin(channel.id)
                            }
                        }
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
        let pinned = vm.isPinned(channel.id)
        let number = vm.tvChannelNumber(for: channel.id)
        HStack(alignment: .top, spacing: 6) {
            if let number {
                Text("\(number)")
                    .font(.caption2.monospacedDigit().bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.accentColor.opacity(0.35))
                    )
                    .accessibilityLabel("Channel \(number)")
            }

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

            if pinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Pinned to remote")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(pinned ? Color.yellow.opacity(0.10) : Color.white.opacity(0.05))
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
