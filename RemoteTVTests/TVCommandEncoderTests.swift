import Foundation
import Testing
import RemoteTVCore
@testable import RemoteTV

struct TVCommandEncoderTests {
    @Test func payloadHasTopLevelMethod() throws {
        let data = try TVCommandEncoder.payload(for: .volumeUp)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["method"] as? String == "ms.remote.control")
    }

    @Test func payloadParamsUseSamsungKeys() throws {
        let data = try TVCommandEncoder.payload(for: .volumeUp)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let params = json?["params"] as? [String: Any]
        #expect(params?["Cmd"] as? String == "Click")
        #expect(params?["Option"] as? String == "false")
        #expect(params?["TypeOfRemote"] as? String == "SendRemoteKey")
    }

    @Test(arguments: TVCommand.allCases)
    func payloadContainsRawKeyCode(for command: TVCommand) throws {
        let data = try TVCommandEncoder.payload(for: command)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let params = json?["params"] as? [String: Any]
        #expect(params?["DataOfCmd"] as? String == command.rawValue)
    }

    @Test func textPayloadUsesSendInputStringWithBase64() throws {
        let data = try TVCommandEncoder.textPayload(for: "next channel")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["method"] as? String == "ms.remote.control")
        let params = json?["params"] as? [String: Any]
        #expect(params?["TypeOfRemote"] as? String == "SendInputString")
        #expect(params?["DataOfCmd"] as? String == "base64")
        // Cmd carries the base64 of the UTF-8 text…
        #expect(params?["Cmd"] as? String == Data("next channel".utf8).base64EncodedString())
        // …and the key-press-only "Option" field must be absent for text frames.
        #expect(params?["Option"] == nil)
    }

    @Test func commandKeyCodesMatchSamsungProtocol() {
        #expect(TVCommand.volumeUp.rawValue == "KEY_VOLUP")
        #expect(TVCommand.volumeDown.rawValue == "KEY_VOLDOWN")
        #expect(TVCommand.mute.rawValue == "KEY_MUTE")
        #expect(TVCommand.up.rawValue == "KEY_UP")
        #expect(TVCommand.down.rawValue == "KEY_DOWN")
        #expect(TVCommand.left.rawValue == "KEY_LEFT")
        #expect(TVCommand.right.rawValue == "KEY_RIGHT")
        #expect(TVCommand.enter.rawValue == "KEY_ENTER")
        #expect(TVCommand.back.rawValue == "KEY_RETURN")
        #expect(TVCommand.home.rawValue == "KEY_HOME")
        #expect(TVCommand.exit.rawValue == "KEY_EXIT")
        #expect(TVCommand.liveTV.rawValue == "KEY_TV")
        #expect(TVCommand.power.rawValue == "KEY_POWER")
        #expect(TVCommand.sleepTimer.rawValue == "KEY_SLEEP")
        #expect(TVCommand.playPause.rawValue == "KEY_PLAY")
        #expect(TVCommand.captions.rawValue == "KEY_CAPTION")
    }
}
