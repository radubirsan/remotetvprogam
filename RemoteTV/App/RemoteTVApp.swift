import AppIntents
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
        let service = SamsungTVService(
            tokenStore: tokenStore,
            rememberedTVsStore: rememberedTVsStore,
            deviceInfoService: deviceInfo
        )
        let wakeService = UDPBroadcastWakeService()
        _service = State(initialValue: service)
        self.rememberedTVsStore = rememberedTVsStore
        self.wakeService = wakeService
        self.discoveryService = BonjourDiscoveryService()

        // Back the App Intents (Siri / Shortcuts / Control Center) with the SAME service
        // instance the UI uses, so an intent fired while the app is open reuses the live
        // socket instead of opening a second one. `TVIntentsController.resolve()` returns
        // this when running in the app process; the Control Center extension has its own
        // process and falls back to a standalone stack built from shared storage.
        TVIntentsController.shared = TVIntentsController(
            service: service,
            wakeService: wakeService,
            rememberedTVsStore: rememberedTVsStore
        )
        // (Re)index the Siri vocabulary for parameterized App Shortcut phrases — the
        // "open <app>" phrase resolves against the TVAppEntity catalog, and entity-backed
        // parameters aren't indexed automatically the way AppEnums are.
        RemoteTVAppShortcuts.updateAppShortcutParameters()
        
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
