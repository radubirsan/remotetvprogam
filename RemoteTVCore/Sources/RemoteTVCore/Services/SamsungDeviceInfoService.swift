import Foundation

/// One-shot `GET http://<ip>:8001/api/v2/` probe that surfaces the fields we need for Wake-on-LAN
/// and persistence: `device.wifiMac`, `device.name`, `device.modelName`.
///
/// The TV exposes this over plain HTTP on port 8001 regardless of whether the remote-control
/// channel runs on `ws://8001` or `wss://8002`, so the service doesn't depend on
/// ``TVConnectionMode``.
public struct SamsungDeviceInfoService: Sendable {
    public struct Info: Sendable, Equatable {
        public let name: String
        public let modelName: String
        public let wifiMac: String?
        /// Last reported power state from `device.PowerState`. Modern Tizen returns
        /// `"on"` for awake and either `"off"` or `"standby"` for the low-power state;
        /// missing/unparseable values map to ``TVPowerState/unknown``.
        public let powerState: TVPowerState

        public init(name: String, modelName: String, wifiMac: String?, powerState: TVPowerState) {
            self.name = name
            self.modelName = modelName
            self.wifiMac = wifiMac
            self.powerState = powerState
        }
    }

    private let session: URLSession
    private let timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 3) {
        self.session = session
        self.timeout = timeout
    }

    public func fetch(ip: String) async throws -> Info {
        guard var components = URLComponents(string: "http://\(ip):8001/api/v2/") else {
            throw TVServiceError.deviceInfoFailure("Bad URL for \(ip)")
        }
        components.scheme = "http"
        guard let url = components.url else {
            throw TVServiceError.deviceInfoFailure("Bad URL for \(ip)")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpMethod = "GET"

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TVServiceError.deviceInfoFailure(String(describing: error))
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TVServiceError.deviceInfoFailure("HTTP \(http.statusCode)")
        }

        do {
            let payload = try JSONDecoder().decode(RawPayload.self, from: data)
            return Info(
                name: payload.device.name ?? "Samsung TV",
                modelName: payload.device.modelName ?? "",
                wifiMac: Self.normalizeMAC(payload.device.wifiMac),
                powerState: Self.parsePowerState(payload.device.powerState)
            )
        } catch {
            throw TVServiceError.deviceInfoFailure("Malformed JSON: \(error)")
        }
    }

    public static func parsePowerState(_ raw: String?) -> TVPowerState {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else {
            return .unknown
        }
        switch raw {
        case "on":               return .on
        case "off", "standby":   return .off
        default:                 return .unknown
        }
    }

    /// Samsung returns MACs as `aa:bb:cc:dd:ee:ff` but has been seen to return empty strings
    /// on models where Wi-Fi is off — treat those as "no MAC".
    public static func normalizeMAC(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private struct RawPayload: Decodable {
        let device: Device

        struct Device: Decodable {
            let name: String?
            let modelName: String?
            let wifiMac: String?
            let powerState: String?

            enum CodingKeys: String, CodingKey {
                case name
                case modelName
                case wifiMac
                /// Samsung returns the field with a capital `P` — explicit mapping so
                /// Swift's default lowerCamelCase strategy doesn't miss it.
                case powerState = "PowerState"
            }
        }
    }
}
