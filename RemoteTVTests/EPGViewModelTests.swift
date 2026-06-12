import Foundation
import Testing
@testable import RemoteTV

@MainActor
struct EPGViewModelTests {

    // MARK: - Tune macro (pure)

    @Test func tuneCommandsSplitsDigitsAndAppendsEnter() {
        #expect(EPGViewModel.tuneCommands(for: 105) == [.digit1, .digit0, .digit5, .enter])
    }

    @Test func tuneCommandsSingleDigit() {
        #expect(EPGViewModel.tuneCommands(for: 7) == [.digit7, .enter])
    }

    @Test func instanceTuneCommandsResolvesKnownChannel() {
        let vm = EPGViewModel()
        // "Digi.Sport.1.ro" is channel 1 in KnownChannelNumbers — the macro is one
        // digit plus the delay-skipping Enter.
        #expect(vm.tuneCommands(for: "Digi.Sport.1.ro") == [.digit1, .enter])
    }

    @Test func instanceTuneCommandsNilForUnknownChannel() {
        let vm = EPGViewModel()
        #expect(vm.tuneCommands(for: "No.Such.Channel.xx") == nil)
        #expect(vm.canTune("No.Such.Channel.xx") == false)
    }

    // MARK: - Channel filtering

    @Test func emptySearchReturnsFullKnownLineup() {
        let vm = EPGViewModel()
        // No guide loaded: every known id is synthesized into a placeholder channel,
        // so the list mirrors the whole tunable lineup.
        #expect(vm.filteredChannels.count == KnownChannelNumbers.orderedIDs.count)
    }

    @Test func searchFiltersByDisplayName() {
        let vm = EPGViewModel()
        vm.searchText = "Eurosport"
        let names = vm.filteredChannels.map(\.primaryName)
        #expect(!names.isEmpty)
        #expect(names.allSatisfy { $0.localizedStandardContains("Eurosport") })
    }

    @Test func searchIsCaseInsensitive() {
        let vm = EPGViewModel()
        vm.searchText = "eurosport"
        #expect(!vm.filteredChannels.isEmpty)
    }

    @Test func searchWithNoMatchReturnsEmpty() {
        let vm = EPGViewModel()
        vm.searchText = "zzz-no-such-channel"
        #expect(vm.filteredChannels.isEmpty)
    }
}
