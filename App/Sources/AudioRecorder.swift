import AVFoundation
import os

/// Records the default microphone as 16 kHz mono Float32, the format Whisper expects.
/// The engine only runs while recording, so the mic indicator is off otherwise.
final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!
    private let samples = OSAllocatedUnfairLock(initialState: [Float]())
    // Written before the tap is installed, read only on the audio thread.
    private var converter: AVAudioConverter?

    private(set) var isRecording = false

    func start() throws {
        guard !isRecording else { return }
        samples.withLock { $0.removeAll(keepingCapacity: true) }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0,
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        else { throw RecorderError.noInputDevice }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        isRecording = true
    }

    /// Stops recording and returns everything captured.
    func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        return samples.withLock { $0 }
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        let feeder = BufferFeeder(buffer)
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            feeder.next(status)
        }
        guard error == nil, let channel = output.floatChannelData?[0] else { return }

        let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        samples.withLock { $0.append(contentsOf: chunk) }
    }

    enum RecorderError: LocalizedError {
        case noInputDevice

        var errorDescription: String? {
            "No microphone is available."
        }
    }
}

/// Hands one buffer to AVAudioConverter, then reports "no more data for now".
private final class BufferFeeder: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let buffer else {
            status.pointee = .noDataNow
            return nil
        }
        self.buffer = nil
        status.pointee = .haveData
        return buffer
    }
}
