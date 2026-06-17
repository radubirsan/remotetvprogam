import Combine
import RemoteTVCore
import SwiftUI

/// TV Guide screen — a dark, skeuomorphic channel guide redesigned to match the
/// `design_handoff_another_remote` "TV Guide" mock. Shows what's on Romanian TV right
/// now (featured "Live Now" card + per-channel now/next rows) and drills into a full
/// per-channel daily schedule.
///
/// Pushed from ``RemoteView``'s TV Guide toolbar button. Tapping a channel (or the
/// featured card) sets `vm.selectedChannelID`, which pushes ``ChannelScheduleScreen`` via
/// `navigationDestination(item:)` — so each level gets a real navigation entry with its
/// own native back button and left-edge swipe-to-go-back.
@MainActor
struct RemoteSidePanelEPG: View {
    @Bindable var vm: EPGViewModel
    /// Dispatches a sequence of TV commands. Supplied by `RemoteView` so the panel can
    /// fire the Tune-to-channel macro through the same `RemoteViewModel.send` path the
    /// rest of the remote uses.
    let onDispatchMacro: ([TVCommand]) async -> Void

    /// Drives live progress bars + "Ends in N min". Bumped every 30s so the guide stays
    /// honest without a per-frame timeline.
    @State private var now: Date = .now

    var body: some View {
        ZStack {
            GuidePalette.screenBackground.ignoresSafeArea()

            Group {
                if let error = vm.lastError, vm.guide == nil {
                    errorView(error)
                        .padding(.horizontal, 20)
                } else if vm.isLoading && vm.guide == nil {
                    ProgressView()
                        .tint(GuidePalette.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    channelListScreen
                }
            }
        }
        .colorScheme(.dark)
        .task { await vm.loadIfNeeded() }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
        .navigationDestination(item: $vm.selectedChannelID) { channelID in
            ChannelScheduleScreen(vm: vm, channelID: channelID, onDispatchMacro: onDispatchMacro)
        }
    }

    // MARK: - List screen

    @ViewBuilder
    private var channelListScreen: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let featuredID = vm.featuredChannelID(at: now),
               let featured = vm.channel(withID: featuredID) {
                featuredCard(featured)
            }
           // headerRow
            searchBar
            categoryChips

            

           // listHeader
            channelScroll
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TV Guide")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(.white)
                Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()) + " · "
                     + now.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12.5))
                    .foregroundStyle(GuidePalette.tertiary)
            }

            Spacer()

            Button {
                Task { await vm.reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(GuidePalette.secondary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.white.opacity(0.05)))
                    .overlay {
                        if vm.isLoading {
                            ProgressView().tint(GuidePalette.secondary)
                        }
                    }
            }
            .disabled(vm.isLoading)
            .accessibilityLabel("Refresh TV guide")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(GuidePalette.tertiary)
            TextField(
                "",
                text: $vm.searchText,
                prompt: Text("Search channels & shows").foregroundColor(GuidePalette.tertiary)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .tint(GuidePalette.accent)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            if !vm.searchText.isEmpty {
                Button {
                    vm.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(GuidePalette.tertiary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.05)))
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GuideCategory.allCases) { category in
                    let selected = vm.selectedCategory == category
                    Button {
                        vm.selectedCategory = category
                    } label: {
                        Text(category.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(selected ? GuidePalette.chipSelectedText : GuidePalette.chipText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(selected ? GuidePalette.accent : Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
        }
    }

    private var listHeader: some View {
        HStack {
            Text(vm.selectedCategory == .all ? "ALL CHANNELS" : vm.selectedCategory.title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(GuidePalette.faint)
            Spacer()
            Text("On Now")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GuidePalette.accent)
        }
        .padding(.bottom, -4)
    }

    private var channelScroll: some View {
        let channels = vm.filteredChannels
        return Group {
            if channels.isEmpty {
                Text(emptyListMessage)
                    .font(.footnote)
                    .foregroundStyle(GuidePalette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(channels) { channel in
                            channelRow(channel)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var emptyListMessage: String {
        if !vm.searchText.isEmpty {
            "No channels match \"\(vm.searchText)\"."
        } else {
            "Nothing in \(vm.selectedCategory.title) right now."
        }
    }

    // MARK: - Featured card

    @ViewBuilder
    private func featuredCard(_ channel: EPGChannel) -> some View {
        let tint = GuidePalette.tint(for: vm.tvChannelNumber(for: channel.id))
        let programme = vm.nowPlaying(for: channel.id, at: now)

        Button {
            vm.selectedChannelID = channel.id
        } label: {
            ZStack(alignment: .bottomLeading) {
                // Badges
                VStack {
                    HStack(alignment: .top) {
                        liveBadge
                        Spacer()
                        Text("CH \(vm.tvChannelNumber(for: channel.id).map(String.init) ?? "–") · \(channel.primaryName)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(programme?.title ?? channel.primaryName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    if let programme {
                        Text(timeRange(programme) + endsInSuffix(programme))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
            }
            .padding(16)
            .frame(height: 120)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    stops: [
                        .init(color: tint.opacity(0.8), location: 0),
                        .init(color: GuidePalette.cardFade, location: 0.75),
                        .init(color: GuidePalette.cardFade, location: 1),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: tint.opacity(0.25), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .contextMenu { rowMenu(for: channel) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live now on \(channel.primaryName): \(programme?.title ?? "unknown programme")")
    }

    private var liveBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(GuidePalette.liveDot)
                .frame(width: 6, height: 6)
                .shadow(color: GuidePalette.liveDot, radius: 3)
            Text("LIVE NOW")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(.black.opacity(0.3)))
    }

    // MARK: - Channel row

    @ViewBuilder
    private func channelRow(_ channel: EPGChannel) -> some View {
        Button {
            vm.selectedChannelID = channel.id
        } label: {
            HStack(alignment: .center, spacing: 12) {
                channelBadge(channel)
                programInfo(channel)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(.white.opacity(0.05)).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu { rowMenu(for: channel) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: channel))
    }

    private func channelBadge(_ channel: EPGChannel) -> some View {
        let tint = GuidePalette.tint(for: vm.tvChannelNumber(for: channel.id))
        let pinned = vm.isPinned(channel.id)
        return VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.6)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .overlay {
                        Text(vm.tvChannelNumber(for: channel.id).map(String.init) ?? "–")
                            .font(.system(size: 16, weight: .heavy).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    .shadow(color: tint.opacity(0.25), radius: 8, y: 3)

                if pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Circle().fill(.black.opacity(0.45)))
                        .offset(x: 5, y: -5)
                }
            }
            Text(channel.primaryName)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(GuidePalette.tertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 52)
        }
        .frame(width: 52)
    }

    @ViewBuilder
    private func programInfo(_ channel: EPGChannel) -> some View {
        let programme = vm.nowPlaying(for: channel.id, at: now)
        VStack(alignment: .leading, spacing: 3) {
            if let programme {
                HStack(spacing: 7) {
                    categoryTag(for: programme)
                    Text(timeRange(programme))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(GuidePalette.tertiary)
                }
                Text(programme.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(GuidePalette.primaryText)
                    .lineLimit(1)

                ProgressTrack(fraction: vm.progress(of: programme, at: now))
                    .padding(.top, 4)

                nextLine(for: channel)
            } else {
                Text("No guide data right now")
                    .font(.system(size: 13))
                    .foregroundStyle(GuidePalette.tertiary)
                    .padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func nextLine(for channel: EPGChannel) -> some View {
        if let next = vm.nextProgramme(for: channel.id, after: now) {
            (
                Text(next.start, format: .dateTime.hour().minute())
                    .foregroundColor(GuidePalette.nextTime).bold()
                + Text("  Next: \(next.title)")
                    .foregroundColor(GuidePalette.faint)
            )
            .font(.system(size: 11))
            .lineLimit(1)
            .padding(.top, 2)
        }
    }

    private func categoryTag(for programme: EPGProgramme) -> some View {
        let raw = programme.categories.first ?? "Now"
        let isLive = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .contains("live")
        return Text(raw.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(isLive ? GuidePalette.liveText : GuidePalette.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isLive ? GuidePalette.liveTagBg : Color.white.opacity(0.06))
            )
            .lineLimit(1)
    }

    // MARK: - Row context menu (shared by rows + featured)

    @ViewBuilder
    private func rowMenu(for channel: EPGChannel) -> some View {
        if let number = vm.tvChannelNumber(for: channel.id) {
            Button("Tune to channel \(number)", systemImage: "tv.badge.wifi") {
                tune(channel.id)
            }
        }
        Button(
            vm.isPinned(channel.id) ? "Unpin from remote" : "Pin as TV's current channel",
            systemImage: vm.isPinned(channel.id) ? "pin.slash" : "pin"
        ) {
            vm.togglePin(channel.id)
        }
    }

    private func tune(_ channelID: String) {
        Task {
            if let commands = vm.tuneCommands(for: channelID) {
                await onDispatchMacro(commands)
            }
            vm.pinnedChannelID = channelID
        }
    }

    // MARK: - Formatting helpers

    private func timeRange(_ programme: EPGProgramme) -> String {
        let start = programme.start.formatted(.dateTime.hour().minute())
        let stop = programme.stop.formatted(.dateTime.hour().minute())
        return "\(start) – \(stop)"
    }

    private func endsInSuffix(_ programme: EPGProgramme) -> String {
        let remaining = programme.stop.timeIntervalSince(now)
        guard remaining > 0 else { return "" }
        let minutes = Int((remaining / 60).rounded())
        return minutes > 0 ? " · Ends in \(minutes) min" : ""
    }

    // MARK: - Accessibility

    private func accessibilityLabel(for channel: EPGChannel) -> String {
        if let now = vm.nowPlaying(for: channel.id, at: now) {
            "\(channel.primaryName), now playing \(now.title)"
        } else {
            "\(channel.primaryName), no current programme"
        }
    }

    // MARK: - Error

    @ViewBuilder
    private func errorView(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Couldn't load TV guide", systemImage: "exclamationmark.triangle")
                .font(.footnote.bold())
                .foregroundStyle(.orange)
            Text(error)
                .font(.caption2)
                .foregroundStyle(GuidePalette.secondary)
                .lineLimit(3)
            Button("Retry") {
                Task { await vm.reload() }
            }
            .buttonStyle(.borderedProminent)
            .tint(GuidePalette.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Channel schedule (pushed)

/// A single channel's full schedule for today — pushed onto the navigation stack from the
/// guide list. Lives behind a real navigation entry so it gets the native back button and
/// left-edge swipe-to-go-back for free; Tune / Pin ride in the nav-bar toolbar.
@MainActor
private struct ChannelScheduleScreen: View {
    @Bindable var vm: EPGViewModel
    let channelID: String
    let onDispatchMacro: ([TVCommand]) async -> Void

    @State private var now: Date = .now

    private var channel: EPGChannel? { vm.channel(withID: channelID) }

    var body: some View {
        ZStack {
            GuidePalette.screenBackground.ignoresSafeArea()
            content
        }
        .colorScheme(.dark)
        .navigationTitle(channel?.primaryName ?? "Channel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now = $0 }
        .toolbar {
            if let number = vm.tvChannelNumber(for: channelID) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { tune() } label: {
                        Label("Tune \(number)", systemImage: "tv.badge.wifi")
                    }
                    .tint(GuidePalette.accent)
                    .accessibilityLabel("Tune the TV to channel \(number)")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { vm.togglePin(channelID) } label: {
                    Image(systemName: vm.isPinned(channelID) ? "pin.fill" : "pin")
                }
                .tint(vm.isPinned(channelID) ? GuidePalette.accent : GuidePalette.secondary)
                .accessibilityLabel(vm.isPinned(channelID) ? "Unpin from remote" : "Pin as TV's current channel")
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerStrip

            let programmes = vm.programmes(forChannel: channelID, on: now)
            if programmes.isEmpty {
                Text("No programmes in the feed for today.")
                    .font(.footnote)
                    .foregroundStyle(GuidePalette.secondary)
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(programmes) { programmeRow($0) }
                        }
                    }
                    .scrollIndicators(.hidden)
                    // Land on what's on now (or the next show) instead of the top of the
                    // day. `onAppear` fires after the first layout pass, so the lazy rows
                    // exist to scroll to.
                    .onAppear {
                        guard let target = scrollTarget(in: programmes) else { return }
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// The programme to reveal when the schedule opens: whatever's live now, else the
    /// next show to start. Nil when the day's already over (leaves the list at the top).
    private func scrollTarget(in programmes: [EPGProgramme]) -> EPGProgramme.ID? {
        if let live = programmes.first(where: { $0.isLive(at: now) }) { return live.id }
        return programmes.first(where: { $0.start > now })?.id
    }

    private var headerStrip: some View {
        let tint = GuidePalette.tint(for: vm.tvChannelNumber(for: channelID))
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [tint, tint.opacity(0.6)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 38, height: 38)
                .overlay {
                    Text(vm.tvChannelNumber(for: channelID).map(String.init) ?? "–")
                        .font(.system(size: 14, weight: .heavy).monospacedDigit())
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text("Today's schedule")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(now, format: .dateTime.weekday(.wide).day().month())
                    .font(.system(size: 12))
                    .foregroundStyle(GuidePalette.tertiary)
            }
            Spacer()
        }
    }

    private func programmeRow(_ programme: EPGProgramme) -> some View {
        let isLive = programme.isLive(at: now)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(programme.start, format: .dateTime.hour().minute())
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(isLive ? .white : GuidePalette.secondary)
                Text(programme.stop, format: .dateTime.hour().minute())
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(GuidePalette.tertiary)
            }
            .frame(width: 48, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(programme.title)
                    .font(.system(size: 14, weight: isLive ? .bold : .regular))
                    .foregroundStyle(GuidePalette.primaryText)
                    .lineLimit(2)
                if let subtitle = programme.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(GuidePalette.secondary)
                        .lineLimit(1)
                }
                if isLive {
                    ProgressTrack(fraction: vm.progress(of: programme, at: now))
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isLive ? GuidePalette.accent.opacity(0.12) : Color.white.opacity(0.04))
        )
        .overlay(alignment: .leading) {
            if isLive {
                RoundedRectangle(cornerRadius: 2)
                    .fill(GuidePalette.accent)
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: programme, isLive: isLive))
    }

    private func tune() {
        Task {
            if let commands = vm.tuneCommands(for: channelID) {
                await onDispatchMacro(commands)
            }
            vm.pinnedChannelID = channelID
        }
    }

    private func accessibilityLabel(for programme: EPGProgramme, isLive: Bool) -> String {
        let prefix = isLive ? "Now playing: " : ""
        let times = "\(programme.start.formatted(date: .omitted, time: .shortened)) to \(programme.stop.formatted(date: .omitted, time: .shortened))"
        return "\(prefix)\(programme.title), \(times)"
    }
}

// MARK: - Progress track

/// 3 pt accent-filled progress bar over a faint white track. Used by both the channel
/// rows and the featured card.
private struct ProgressTrack: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08))
                Capsule()
                    .fill(GuidePalette.accent)
                    .frame(width: max(0, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 3)
    }
}

// MARK: - Palette

/// Design tokens for the redesigned TV Guide, lifted from
/// `design_handoff_another_remote/README.md` (dark-mode only).
private enum GuidePalette {
    static let screenBackground = LinearGradient(
        colors: [Color(hex: 0x121214), Color(hex: 0x08080A)],
        startPoint: .top, endPoint: .bottom
    )
    static let cardFade = Color(hex: 0x1A1A1D)

    static let accent = Color(hex: 0xFF6B5A)            // Ember (default)
    static let primaryText = Color(hex: 0xE8E8EA)
    static let secondary = Color(hex: 0x9A9A9E)
    static let tertiary = Color(hex: 0x6A6A6E)
    static let faint = Color(hex: 0x5A5A5E)
    static let nextTime = Color(hex: 0x7A7A7E)

    static let chipText = Color(hex: 0xB0B0B4)
    static let chipSelectedText = Color(hex: 0x1A1A1D)

    static let liveDot = Color(hex: 0xFF4444)
    static let liveText = Color(hex: 0xFF6B6B)
    static let liveTagBg = Color(red: 230.0 / 255, green: 57.0 / 255, blue: 70.0 / 255).opacity(0.18)

    /// Channel-badge tints (guide). Assigned deterministically by TV channel number so a
    /// channel keeps the same colour across launches; falls back to grey when unknown.
    private static let tints: [Color] = [
        0xE63946, 0x2A9D8F, 0xE9C46A, 0x457B9D,
        0xF4A261, 0x8367C7, 0xEF476F, 0x06A77D,
    ].map { Color(hex: $0) }

    static func tint(for channelNumber: Int?) -> Color {
        guard let n = channelNumber else { return Color(hex: 0x4A4A4E) }
        return tints[abs(n) % tints.count]
    }
}

private extension Color {
    /// `0xRRGGBB` literal → `Color`.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
