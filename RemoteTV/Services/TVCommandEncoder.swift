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
        try rawKeyPayload(keyCode: command.rawValue)
    }

    /// Builds a `SendRemoteKey` frame for an arbitrary key code and gesture.
    /// `cmd` is `"Click"` for a normal tap, or `"Press"`/`"Release"` to simulate a
    /// press-and-hold (some functions — e.g. the physical remote's voice button —
    /// only fire on a hold). Used by both the typed ``TVCommand`` keys and the
    /// experimental Bixby-probe buttons, which need to try codes not in the enum.
    static func rawKeyPayload(keyCode: String, cmd: String = "Click") throws -> Data {
        let payload = Payload(
            method: "ms.remote.control",
            params: .init(
                cmd: cmd,
                dataOfCmd: keyCode,
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

    /// Builds the voice (mic) key frame used to toggle Bixby's listening state, per
    /// `Bixby.md`. `cmd` is `"Press"` or `"Release"` — the two are sent back-to-back to
    /// toggle. Differs from a normal key frame in one detail the protocol is picky
    /// about: `Option` is a JSON **boolean** `false`, not the string `"false"`.
    static func voiceKeyPayload(cmd: String) throws -> Data {
        let payload = VoiceKeyPayload(
            method: "ms.remote.control",
            params: .init(cmd: cmd, typeOfRemote: "SendRemoteKey", dataOfCmd: "KEY_BT_VOICE", option: false)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    /// The fixed UTF-8 JSON header that precedes every voice audio chunk (84 bytes).
    private static let voiceAudioHeader = Data(
        #"{"method":"ms.voice.control","params":{"to":"broadcast","event":"ms.voice.control"}}"#.utf8
    )

    /// Wraps a raw PCM chunk (16-bit LE, mono, 16 kHz) in the binary voice frame the TV
    /// expects: a big-endian uint16 header length, the JSON header, then the audio.
    /// Sent as a single binary WebSocket frame. An end-of-utterance marker is just this
    /// same frame with a tiny payload (e.g. 4 zero bytes).
    static func voiceAudioFrame(pcm: Data) -> Data {
        let header = voiceAudioHeader
        let length = UInt16(header.count)
        var frame = Data(capacity: 2 + header.count + pcm.count)
        frame.append(UInt8(length >> 8))
        frame.append(UInt8(length & 0xFF))
        frame.append(header)
        frame.append(pcm)
        return frame
    }

    private struct VoiceKeyPayload: Encodable {
        let method: String
        let params: Params

        struct Params: Encodable {
            let cmd: String
            let typeOfRemote: String
            let dataOfCmd: String
            let option: Bool

            enum CodingKeys: String, CodingKey {
                case cmd = "Cmd"
                case dataOfCmd = "DataOfCmd"
                case option = "Option"
                case typeOfRemote = "TypeOfRemote"
            }
        }
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
