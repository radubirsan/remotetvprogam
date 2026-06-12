import Foundation

/// First capture group of `pattern` in `string`, or `nil`. Small shared regex helper for
/// scraping the DIAL XML (`SamsungTVService.fetchYouTubeScreenId`) and the Lounge
/// responses below without a full parser.
func firstRegexMatch(in string: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(string.startIndex..., in: string)
    guard let match = regex.firstMatch(in: string, range: range),
          match.numberOfRanges > 1,
          let group = Range(match.range(at: 1), in: string) else { return nil }
    return String(string[group])
}

/// Minimal client for YouTube's private **Lounge** API — the cloud protocol the YouTube
/// phone app and Chromecast use to control the YouTube-on-TV app. It is undocumented and
/// **can break whenever Google changes it**. The wire format here is derived from the
/// `casttube` (pychromecast) and `ytcast` projects.
///
/// Given a `screenId` (read from the TV's DIAL `additionalData`), ``play(screenId:videoId:listId:startSeconds:)``
/// runs the three-step handshake — fetch a lounge token, open a bind session to obtain the
/// `SID`/`gsessionid`, then send a `setPlaylist` command — to start a specific video on the
/// screen, no on-TV pairing code required.
struct YouTubeLoungeClient: Sendable {
    enum LoungeError: Error, CustomStringConvertible {
        case http(stage: String, status: Int, body: String)
        case missingToken
        case missingSessionIds
        case badResponse
        case badURL

        var description: String {
            switch self {
            case let .http(stage, status, body): return "\(stage) HTTP \(status) \(body)"
            case .missingToken:      return "no loungeToken in response"
            case .missingSessionIds: return "no SID/gsessionid in bind response"
            case .badResponse:       return "unexpected response"
            case .badURL:            return "could not build bind URL"
            }
        }
    }

    /// Name shown on the TV's "connected device" indicator.
    let senderName: String

    private static let tokenURL = URL(string: "https://www.youtube.com/api/lounge/pairing/get_lounge_token_batch")!
    private static let bindURL = "https://www.youtube.com/api/lounge/bc/bind"
    private static let origin = "https://www.youtube.com"
    // A desktop UA — the Lounge endpoint is pickier when the UA looks like an unknown client.
    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.45 Safari/537.36"

    func play(screenId: String, videoId: String, listId: String?, startSeconds: Int) async throws {
        let token = try await loungeToken(screenId: screenId)
        let session = try await sessionIds(loungeToken: token)
        try await setPlaylist(
            loungeToken: token,
            session: session,
            videoId: videoId,
            listId: listId,
            startSeconds: startSeconds
        )
    }

    // MARK: - Steps

    /// `POST get_lounge_token_batch` with `screen_ids=<id>` → `screens[0].loungeToken`.
    private func loungeToken(screenId: String) async throws -> String {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        applyCommonHeaders(&request, formEncoded: true)
        request.httpBody = Self.formBody(["screen_ids": screenId])

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.requireOK(response, data, stage: "lounge token")
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let screens = json["screens"] as? [[String: Any]],
            let token = screens.first?["loungeToken"] as? String, !token.isEmpty
        else { throw LoungeError.missingToken }
        return token
    }

    /// Opens a bind session (RID=1, all params in the query string, empty body) and scrapes
    /// the `SID` (`"c","…"`) and `gsessionid` (`"S","…"`) out of the chunked response.
    private func sessionIds(loungeToken: String) async throws -> (sid: String, gsession: String) {
        var request = URLRequest(url: try Self.bindRequestURL(queryItems: [
            .init(name: "CVER", value: "1"),
            .init(name: "RID", value: "1"),
            .init(name: "VER", value: "8"),
            .init(name: "app", value: "youtube-desktop"),
            .init(name: "device", value: "REMOTE_CONTROL"),
            .init(name: "id", value: "remote"),
            .init(name: "loungeIdToken", value: loungeToken),
            .init(name: "name", value: senderName),
        ]))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        applyCommonHeaders(&request, formEncoded: false)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.requireOK(response, data, stage: "bind")
        let body = String(data: data, encoding: .utf8) ?? ""
        guard
            let sid = firstRegexMatch(in: body, pattern: "\"c\",\"([^\"]+)\""),
            let gsession = firstRegexMatch(in: body, pattern: "\"S\",\"([^\"]+)\"")
        else { throw LoungeError.missingSessionIds }
        return (sid, gsession)
    }

    /// `POST bc/bind?SID=…&gsessionid=…` (RID=2) with the `setPlaylist` command in the form
    /// body. `req0_listId` is included for a radio/playlist mix; `req0_videoIds` carries the
    /// single id so playback starts even when no list is given.
    private func setPlaylist(
        loungeToken: String,
        session: (sid: String, gsession: String),
        videoId: String,
        listId: String?,
        startSeconds: Int
    ) async throws {
        var fields = [
            "count": "1",
            "req0__sc": "setPlaylist",
            "req0_videoId": videoId,
            "req0_currentTime": String(startSeconds),
            "req0_currentIndex": "0",
            "req0_videoIds": videoId,
        ]
        if let listId, !listId.isEmpty { fields["req0_listId"] = listId }

        var request = URLRequest(url: try Self.bindRequestURL(queryItems: [
            .init(name: "CVER", value: "1"),
            .init(name: "RID", value: "2"),
            .init(name: "SID", value: session.sid),
            .init(name: "VER", value: "8"),
            .init(name: "gsessionid", value: session.gsession),
            .init(name: "loungeIdToken", value: loungeToken),
        ]))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        applyCommonHeaders(&request, formEncoded: true)
        request.httpBody = Self.formBody(fields)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.requireOK(response, data, stage: "setPlaylist")
    }

    // MARK: - Helpers

    /// Builds a `bc/bind` URL with the given query items. The base is a constant, but
    /// query values (sender name, session ids) come from outside — so build defensively
    /// instead of force-unwrapping.
    private static func bindRequestURL(queryItems: [URLQueryItem]) throws -> URL {
        var components = URLComponents(string: bindURL)
        components?.queryItems = queryItems
        guard let url = components?.url else { throw LoungeError.badURL }
        return url
    }

    private func applyCommonHeaders(_ request: inout URLRequest, formEncoded: Bool) {
        request.setValue(Self.origin, forHTTPHeaderField: "Origin")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if formEncoded {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
    }

    private static func formBody(_ fields: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return (components.percentEncodedQuery ?? "").data(using: .utf8) ?? Data()
    }

    private static func requireOK(_ response: URLResponse, _ data: Data, stage: String) throws {
        guard let http = response as? HTTPURLResponse else { throw LoungeError.badResponse }
        guard http.statusCode == 200 else {
            throw LoungeError.http(stage: stage, status: http.statusCode,
                                   body: String(data: data.prefix(160), encoding: .utf8) ?? "")
        }
    }
}
