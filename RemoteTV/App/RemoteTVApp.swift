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
        
        Task {
             let epg = EPGClient(configuration: .init(sourceURL:
         EPGClient.Configuration.defaultSourceURL))
             if let now = try? await epg.nowPlaying(on: "Digi.24.HD.ro") {
                 print("Now on Digi 24 HD:", now.title, "until", now.stop)
             }
         }  
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                service: service,
                discovery: discoveryService,
                rememberedTVsStore: rememberedTVsStore,
                wakeService: wakeService
            )
        }
    }
}
