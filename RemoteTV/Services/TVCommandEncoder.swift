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

    /// Builds the payload for typing a UTF-8 string into whatever text field is
    /// focused on the TV (a search box, a login field, etc.). Distinct wire shape from
    /// a key press:
    /// ```
    /// {
    ///   "method": "ms.remote.control",
    ///   "params": {
    ///     "Cmd": "<base64(text)>",
    ///     "DataOfCmd": "base64",
    ///     "TypeOfRemote": "SendInputString"
    ///   }
    /// }
    /// ```
    /// Note there's **no `Option` field** here — the TV rejects the frame if it's
    /// present alongside `SendInputString`. The text only lands if a field on the TV
    /// currently has input focus; otherwise the TV silently drops it.
    static func textPayload(for text: String) throws -> Data {
        let encoded = Data(text.utf8).base64EncodedString()
        let payload = TextPayload(
            method: "ms.remote.control",
            params: .init(
                cmd: encoded,
                dataOfCmd: "base64",
                typeOfRemote: "SendInputString"
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

    private struct TextPayload: Encodable {
        let method: String
        let params: Params

        struct Params: Encodable {
            let cmd: String
            let dataOfCmd: String
            let typeOfRemote: String

            enum CodingKeys: String, CodingKey {
                case cmd = "Cmd"
                case dataOfCmd = "DataOfCmd"
                case typeOfRemote = "TypeOfRemote"
            }
        }
    }
}
