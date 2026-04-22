import Foundation

/// Produces the websocket URL used to open a remote-control channel on a Samsung TV.
///
/// The TV expects the controlling app name as a Base64-encoded `name` query parameter and —
/// once paired — echoes the same pairing `token` back on subsequent connects.
enum TVURLBuilder {
    static let appName = "RemoteTV"
    static let path = "/api/v2/channels/samsung.remote.control"

    static func connectURL(for device: TVDevice, token: String?) throws -> URL {
        guard !device.ip.isEmpty else { throw TVServiceError.invalidIP }

        let encodedName = Data(appName.utf8).base64EncodedString()

        var components = URLComponents()
        components.scheme = device.mode.scheme
        components.host = device.ip
        components.port = device.mode.port
        components.path = path

        var queryItems = [URLQueryItem(name: "name", value: encodedName)]
        if let token, !token.isEmpty {
            queryItems.append(URLQueryItem(name: "token", value: token))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw TVServiceError.invalidURL }
        return url
    }
}
