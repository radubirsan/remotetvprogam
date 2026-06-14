import Foundation
import Testing
@testable import RemoteTV

struct TVIntentEntitiesTests {
    @Test func channelCatalogMirrorsKnownLineup() {
        let channels = TVChannelEntity.all
        #expect(channels.count == KnownChannelNumbers.orderedIDs.count)
        // Ordered by channel number ascending, same as the EPG list.
        #expect(channels.map(\.number) == channels.map(\.number).sorted())
    }

    @Test func channelEntityCarriesHumanReadableName() {
        let digi24 = TVChannelEntity.all.first { $0.id == "Digi.24.HD.ro" }
        #expect(digi24?.name == "Digi 24 HD")
    }

    @Test func appCatalogHasNoDuplicateIDsOrNames() {
        let apps = TVAppEntity.all
        #expect(Set(apps.map(\.id)).count == apps.count)
        #expect(Set(apps.map { $0.name.lowercased() }).count == apps.count)
    }

    @Test func appCatalogPrefersDedicatedShortcutNames() {
        // The dedicated TVApp entries come first, so their canonical names win over
        // any catalog variant of the same app.
        let youtube = TVAppEntity.all.first { $0.id == TVApp.youtube.appID }
        #expect(youtube?.name == "YouTube")
    }

    @Test func channelQueryMatchesBySpokenName() async throws {
        let matches = try await TVChannelQuery().entities(matching: "eurosport")
        #expect(!matches.isEmpty)
        #expect(matches.allSatisfy { $0.name.localizedStandardContains("Eurosport") })
    }
}
