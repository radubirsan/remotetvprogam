import Foundation
import Testing
import RemoteTVCore
@testable import RemoteTV

struct TVURLBuilderTests {
    @Test func plainModeUsesWsSchemeAndPort8001() throws {
        let device = TVDevice(ip: "192.168.1.42", name: "Living Room", mode: .plain)
        let url = try TVURLBuilder.connectURL(for: device, token: nil)
        #expect(url.scheme == "ws")
        #expect(url.port == 8001)
        #expect(url.host == "192.168.1.42")
        #expect(url.path == "/api/v2/channels/samsung.remote.control")
    }

    @Test func secureModeUsesWssSchemeAndPort8002() throws {
        let device = TVDevice(ip: "10.0.0.2", name: "Kitchen", mode: .secure)
        let url = try TVURLBuilder.connectURL(for: device, token: nil)
        #expect(url.scheme == "wss")
        #expect(url.port == 8002)
    }

    @Test func nameIsBase64EncodedAppName() throws {
        let device = TVDevice(ip: "192.168.1.42", name: "Living Room", mode: .plain)
        let url = try TVURLBuilder.connectURL(for: device, token: nil)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let name = items.first(where: { $0.name == "name" })?.value
        #expect(name == Data(TVURLBuilder.appName.utf8).base64EncodedString())
    }

    @Test func tokenAppendedWhenProvided() throws {
        let device = TVDevice(ip: "192.168.1.42", name: "TV", mode: .secure)
        let url = try TVURLBuilder.connectURL(for: device, token: "ABCD1234")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first(where: { $0.name == "token" })?.value == "ABCD1234")
    }

    @Test func tokenOmittedWhenNil() throws {
        let device = TVDevice(ip: "192.168.1.42", name: "TV", mode: .plain)
        let url = try TVURLBuilder.connectURL(for: device, token: nil)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(!items.contains(where: { $0.name == "token" }))
    }

    @Test func tokenOmittedWhenEmpty() throws {
        let device = TVDevice(ip: "192.168.1.42", name: "TV", mode: .plain)
        let url = try TVURLBuilder.connectURL(for: device, token: "")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(!items.contains(where: { $0.name == "token" }))
    }

    @Test func emptyIPThrowsInvalidIP() {
        let device = TVDevice(ip: "", name: "TV", mode: .plain)
        #expect(throws: TVServiceError.invalidIP) {
            _ = try TVURLBuilder.connectURL(for: device, token: nil)
        }
    }
}
