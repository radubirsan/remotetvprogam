import Foundation

/// Builds the JSON payload Samsung TVs expect for a single key press over the remote channel.
///
/// Wire format:
/// ```
/// {
///   "method": "ms.remote.control",
///   "params": {
///     "Cmd": "Click",
///     "DataOfCmd": "KEY_VOLUP",
///     "Option": "false",
///     "TypeOfRemote": "SendRemoteKey"
///   }
/// }
/// ```
enum TVCommandEncoder {
    static func payload(for command: TVCommand) throws -> Data {
        let payload = Payload(
            method: "ms.remote.control",
            params: .init(
                cmd: "Click",
                dataOfCmd: command.rawValue,
                option: "false",
                typeOfRemote: "SendRemoteKey"
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    private struct Payload: Encodable {
        let method: String
        let params: Params

        struct Params: Encodable {
            let cmd: String
            let dataOfCmd: String
            let option: String
            let typeOfRemote: String

            enum CodingKeys: String, CodingKey {
                case cmd = "Cmd"
                case dataOfCmd = "DataOfCmd"
                case option = "Option"
                case typeOfRemote = "TypeOfRemote"
            }
        }
    }
}
