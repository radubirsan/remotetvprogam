import Foundation

// MARK: - Voice (Bixby) streaming — see Bixby.md
//
// The voice session is a self-contained state machine layered on the live control
// socket: open Bixby with a held-down voice key, wait for the TV's
// `ms.voiceApp.recording` event, stream PCM chunks as binary frames, then release
// the key. The stored session state (`voiceRecordingWaiter`, `voiceChunkCount`,
// `voiceSessionActive`) lives in the main class — extensions can't add stored
// instance properties — but every method that touches it is here.
extension SamsungTVService {
    /// How long to wait for the TV's `ms.voiceApp.recording` after opening Bixby.
    static let voiceRecordingTimeout: Duration = .seconds(4)

    public func beginVoiceSession() async throws {
        guard state == .connected, webSocketTask != nil else {
            throw TVServiceError.notConnected
        }
        // Step 1: toggle the voice key on (Press then Release, back-to-back).
        voiceChunkCount = 0
        // Suspend the heartbeat for the whole session — a keepalive-triggered reconnect would
        // call teardown(), failing the recording waiter and closing Bixby.
        voiceSessionActive = true
        do {
            // Hold-to-talk: send only the Press here and KEEP it held while audio streams —
            // this firmware treats an immediate Release as "mic button let go" and closes
            // Bixby right after it opens. The matching Release is sent in endVoiceSession().
            try await transmit(TVCommandEncoder.voiceKeyPayload(cmd: "Press"))
            appendSniff(.info, "voice: opening Bixby, waiting for recording…")
            // Step 2: block until the TV says it's listening.
            do {
                try await awaitVoiceRecording()
            } catch {
                // Don't leave the voice key stuck "held" if Bixby never came up.
                try? await transmit(TVCommandEncoder.voiceKeyPayload(cmd: "Release"))
                throw error
            }
        } catch {
            voiceSessionActive = false
            throw error
        }
        appendSniff(.info, "voice: TV is recording")
    }

    public func sendVoiceChunk(_ pcm: Data) async throws {
        guard state == .connected, let task = webSocketTask else {
            throw TVServiceError.notConnected
        }
        // Step 3: one binary frame per chunk.
        let frame = TVCommandEncoder.voiceAudioFrame(pcm: pcm)
        try await task.send(.data(frame))
        voiceChunkCount += 1
        appendSniff(.outbound, "voice audio chunk #\(voiceChunkCount): \(pcm.count) PCM bytes (\(frame.count)-byte frame)")
    }

    public func endVoiceSession() async {
        guard state == .connected, let task = webSocketTask else { return }
        // Step 4: empty end-of-stream marker, then Release the (held-down) voice key —
        // the Release is what tells Bixby the user "let go" and to process the utterance.
        try? await task.send(.data(TVCommandEncoder.voiceAudioFrame(pcm: Data([0, 0, 0, 0]))))
        try? await transmit(TVCommandEncoder.voiceKeyPayload(cmd: "Release"))
        appendSniff(.info, "voice: end-of-stream marker + Release sent after \(voiceChunkCount) chunks")
        voiceSessionActive = false
    }

    /// Suspends until the receive loop sees `ms.voiceApp.recording`, or throws
    /// ``TVServiceError/voiceNotReady`` after ``voiceRecordingTimeout``. Single-shot:
    /// whichever of event/timeout fires first resumes the continuation and clears it.
    private func awaitVoiceRecording() async throws {
        // A waiter left over from a previous session would be silently overwritten below
        // and never resumed (a hang for whoever awaits it). Only one voice session is
        // supposed to be in flight at a time, so fail any straggler before installing ours.
        failVoiceRecordingWaiter()
        let timeout = Self.voiceRecordingTimeout
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            voiceRecordingWaiter = cont
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.failVoiceRecordingWaiter()
            }
        }
    }

    private func resumeVoiceRecordingWaiter() {
        voiceRecordingWaiter?.resume()
        voiceRecordingWaiter = nil
    }

    func failVoiceRecordingWaiter() {
        voiceRecordingWaiter?.resume(throwing: TVServiceError.voiceNotReady)
        voiceRecordingWaiter = nil
    }

    /// Parses an inbound frame for voice lifecycle events and reacts. Called from the
    /// receive loop alongside ``recordInbound(_:)``.
    func handleVoiceEvent(_ message: URLSessionWebSocketTask.Message) {
        guard let data = messageData(from: message),
              let envelope = try? JSONDecoder().decode(EventEnvelope.self, from: data),
              let event = envelope.event else { return }
        switch event {
        case "ms.voiceApp.recording":
            resumeVoiceRecordingWaiter()
        case "ms.voiceApp.hide":
            appendSniff(.info, "voice: TV finished (ms.voiceApp.hide)")
        default:
            break
        }
    }

    struct EventEnvelope: Decodable {
        let event: String?
    }
}
