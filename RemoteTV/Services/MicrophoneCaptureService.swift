// `@preconcurrency`: AVFAudio isn't fully Sendable-audited, and the converter's input
// block is `@Sendable` even though it runs synchronously inside `convert(to:…)` — so
// capturing the (non-Sendable) input buffer there is safe. Suppresses that warning.
@preconcurrency import AVFoundation
import Foundation
import RemoteTVCore

/// Captures microphone audio and emits it as the raw PCM chunks the Samsung Bixby
/// voice protocol expects: signed 16-bit little-endian, mono, 16 kHz. See `Bixby.md`.
///
/// `AVAudioEngine`'s input tap delivers buffers in the hardware format (typically
/// 48 kHz float); an `AVAudioConverter` resamples and reformats each buffer to the
/// target, and the bytes are accumulated into ~14 KB chunks before being yielded on
/// the returned `AsyncStream`.
///
/// `@unchecked Sendable`: the tap callback runs on a real-time audio thread, but the
/// mutable state it touches (`pending`, `converter`) is only accessed from that single
/// thread between `start()` and `stop()`, and `AsyncStream.Continuation` is itself
/// thread-safe (yielding after `finish()` is a harmless no-op).
final class MicrophoneCaptureService: @unchecked Sendable {

    private let engine = AVAudioEngine()
    private let targetSampleRate: Double = 16_000

    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var continuation: AsyncStream<Data>.Continuation?
    /// Audio gate. The engine is started (warm) *before* the TV is ready, but converted
    /// buffers are discarded until ``beginStreaming()`` opens this — so Bixby only ever
    /// sees audio captured *after* it reported `ms.voiceApp.recording`, and the first
    /// chunk lands with no engine-startup latency (which otherwise made Bixby time out
    /// and close before any audio arrived).
    private var streaming = false
    private var emittedChunks = 0
    private var emittedBytes = 0

    /// Asks for microphone permission, returning whether it's granted. Safe to call
    /// repeatedly — the system only prompts the first time.
    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Starts capture and returns a stream of PCM chunks. Call ``stop()`` to end it
    /// (which flushes any tail audio and finishes the stream).
    func start() throws -> AsyncStream<Data> {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        print("[RemoteTV] mic: input format \(inputFormat.sampleRate)Hz \(inputFormat.channelCount)ch → target 16000Hz mono int16")
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            print("[RemoteTV] mic: ERROR no audio input available")
            throw TVServiceError.microphoneFailure("No audio input available")
        }
        guard
            let target = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: targetSampleRate,
                channels: 1,
                interleaved: true
            ),
            let converter = AVAudioConverter(from: inputFormat, to: target)
        else {
            throw TVServiceError.microphoneFailure("Could not create 16 kHz audio converter")
        }
        self.targetFormat = target
        self.converter = converter
        self.streaming = false

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
        } catch {
            print("[RemoteTV] mic: ERROR audio session: \(error.localizedDescription)")
            throw TVServiceError.microphoneFailure(error.localizedDescription)
        }

        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
        self.continuation = continuation

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("[RemoteTV] mic: ERROR engine.start: \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
            continuation.finish()
            self.continuation = nil
            throw TVServiceError.microphoneFailure(error.localizedDescription)
        }
        print("[RemoteTV] mic: engine warming (gate closed)")
        return stream
    }

    /// Opens the audio gate. Call this the instant the TV reports it's recording, so the
    /// already-warm engine starts emitting chunks immediately.
    func beginStreaming() {
        emittedChunks = 0
        emittedBytes = 0
        streaming = true
        print("[RemoteTV] mic: streaming opened")
    }

    func stop() {
        streaming = false
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        continuation?.finish()
        continuation = nil
        converter = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        print("[RemoteTV] mic: stopped — emitted \(emittedChunks) chunks, \(emittedBytes) PCM bytes total")
    }

    // MARK: - Private

    private func process(_ buffer: AVAudioPCMBuffer) {
        // Drop everything until the gate opens — keeps the engine warm without sending
        // pre-recording audio to the TV.
        guard streaming, let converter, let targetFormat else { return }
        let ratio = targetSampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        // The converter pulls input via a `@Sendable` block; feed our one buffer the
        // first time and signal "no more" after. `fed` is boxed in a reference type so
        // the synchronous block can mutate it without a captured-var warning.
        let fed = FlagBox()
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if fed.value {
                inputStatus.pointee = .noDataNow
                return nil
            }
            fed.value = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            print("[RemoteTV] mic: convert error \(error?.localizedDescription ?? "unknown")")
            return
        }
        guard out.frameLength > 0, let channel = out.int16ChannelData else { return }

        // Yield one frame per converted tap buffer (~85 ms) instead of accumulating a
        // big chunk — so the first audio reaches Bixby within a tap of recording start,
        // not ~half a second later.
        let byteCount = Int(out.frameLength) * MemoryLayout<Int16>.size
        continuation?.yield(Data(bytes: channel[0], count: byteCount))
        emittedChunks += 1
        emittedBytes += byteCount
    }
}

/// One-shot mutable flag, boxed so a `@Sendable` synchronous closure can flip it
/// without tripping captured-`var` concurrency diagnostics.
private final class FlagBox: @unchecked Sendable {
    var value = false
}
