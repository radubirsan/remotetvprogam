import SwiftUI

@main
@MainActor
struct RemoteTVApp: App {
    @State private var service: SamsungTVService
    private let rememberedTVsStore: FileRememberedTVsStore
    private let wakeService: UDPBroadcastWakeService
    private let discoveryService: BonjourDiscoveryService

    init() {
        let tokenStore = KeychainTVTokenStore()
        let rememberedTVsStore = FileRememberedTVsStore()
        let deviceInfo = SamsungDeviceInfoService()
        _service = State(initialValue: SamsungTVService(
            tokenStore: tokenStore,
            rememberedTVsStore: rememberedTVsStore,
            deviceInfoService: deviceInfo
        ))
        self.rememberedTVsStore = rememberedTVsStore
        self.wakeService = UDPBroadcastWakeService()
        self.discoveryService = BonjourDiscoveryService()
    }

    var body: some Scene {
        WindowGroup {
            DiscoveryView(
                service: service,
                discovery: discoveryService,
                rememberedTVsStore: rememberedTVsStore,
                wakeService: wakeService
            )
        }
    }
}
