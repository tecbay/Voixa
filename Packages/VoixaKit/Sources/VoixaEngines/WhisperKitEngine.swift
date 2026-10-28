import Foundation
import VoixaKit
import WhisperKit

/// Whisper running on Apple Silicon through WhisperKit.
///
/// Not thread-safe: callers must not overlap `prepare`, `transcribe` and
/// `unload`. `DictationController` serializes them.
public final class WhisperKitEngine: TranscriptionEngine, @unchecked Sendable {
    public let model: WhisperModel
    private let modelsDirectory: URL
    private let onDownloadProgress: @Sendable (Double) -> Void
    private var whisperKit: WhisperKit?
    public private(set) var loadedMode: ComputeMode?

    public var isLoaded: Bool { whisperKit != nil }

    /// Loads an audio file as 16 kHz mono samples.
    public static func loadAudio(path: String) throws -> [Float] {
        try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
    }

    public init(
        model: WhisperModel,
        modelsDirectory: URL = ModelStore.defaultDirectory,
        onDownloadProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) {
        self.model = model
        self.modelsDirectory = modelsDirectory
        self.onDownloadProgress = onDownloadProgress
    }

    public var isModelDownloaded: Bool {
        ModelStore.isDownloaded(model, in: modelsDirectory)
    }

    /// Downloads the model if needed and loads it. Does nothing if it is
    /// already loaded in the same mode; reloads if the mode differs.
    public func prepare(compute: ComputeMode) async throws {
        if whisperKit != nil {
            guard loadedMode != compute else { return }
            await unload()
        }

        let folder: URL
        if isModelDownloaded {
            folder = ModelStore.folder(for: model, in: modelsDirectory)
        } else {
            folder = try await download()
            ModelStore.markDownloaded(model, in: modelsDirectory)
        }

        let config = WhisperKitConfig(
            modelFolder: folder.path,
            tokenizerFolder: modelsDirectory,
            computeOptions: Debug.computeOverride ?? Self.computeOptions(compute),
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false
        )
        whisperKit = try await WhisperKit(config)
        loadedMode = compute
    }

    /// Frees the model's memory. The next `prepare` loads it again from disk.
    public func unload() async {
        await whisperKit?.unloadModels()
        whisperKit = nil
        loadedMode = nil
    }

    public func transcribe(_ audio: [Float], options: TranscriptionOptions) async throws -> Transcript {
        guard let whisperKit else { throw EngineError.notReady }

        let language = try await resolveLanguage(audio, allowed: options.languages, whisperKit: whisperKit)

        var decoding = DecodingOptions(
            task: .transcribe,
            language: language?.rawValue,
            temperatureFallbackCount: 5,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            chunkingStrategy: .vad
        )
        if let prompt = options.prompt, let tokenizer = whisperKit.tokenizer {
            decoding.promptTokens = tokenizer.encode(text: " " + prompt)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }

        let results = try await whisperKit.transcribe(audioArray: audio, decodeOptions: decoding)
        if Debug.enabled, let t = results.first?.timings {
            Debug.log(String(
                format: "timings: logmels %.3f, encoding %.3f (%d runs), decoding %.3f (%d tokens), fallback %.3f",
                t.logmels, t.encoding, Int(t.totalEncodingRuns), t.decodingLoop, Int(t.totalDecodingLoops), t.decodingFallback
            ))
        }
        let text = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Transcript(text: text, language: language)
    }

    /// Downloads the model, retrying network failures. Files already on disk
    /// are kept, so a retry continues where the last attempt stopped.
    private func download() async throws -> URL {
        let progress = onDownloadProgress
        var attempt = 1
        while true {
            do {
                return try await WhisperKit.download(
                    variant: model.whisperKitVariant,
                    downloadBase: modelsDirectory,
                    progressCallback: { progress($0.fractionCompleted) }
                )
            } catch let error as URLError where attempt < 3 {
                if Debug.enabled { Debug.log("download attempt \(attempt) failed: \(error.localizedDescription)") }
                attempt += 1
                try await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Detects the language, but only picks among those the user speaks.
    private func resolveLanguage(
        _ audio: [Float],
        allowed: [SpokenLanguage],
        whisperKit: WhisperKit
    ) async throws -> SpokenLanguage? {
        guard allowed.count > 1 else { return allowed.first }
        guard let tokenizer = whisperKit.tokenizer,
              let sampler = AllowedLanguageSampler(allowed: allowed, tokenizer: tokenizer)
        else { return nil }

        // Same steps as WhisperKit.detectLangauge, with our sampler.
        let windowSamples = whisperKit.featureExtractor.windowSamples ?? Constants.defaultWindowSamples
        guard let window = whisperKit.audioProcessor.padOrTrim(fromArray: audio, startAt: 0, toLength: windowSamples),
              let mel = try await whisperKit.featureExtractor.logMelSpectrogram(fromAudio: window),
              let encoded = try await whisperKit.audioEncoder.encodeFeatures(mel)
        else { return nil }

        let decoderInputs = try whisperKit.textDecoder.prepareDecoderInputs(
            withPrompt: [tokenizer.specialTokens.startOfTranscriptToken]
        )
        _ = try await whisperKit.textDecoder.detectLanguage(
            from: encoded,
            using: decoderInputs,
            sampler: sampler,
            options: DecodingOptions(),
            temperature: 0
        )
        return sampler.chosen
    }

    /// Splitting encoder and decoder across GPU and Neural Engine was measured
    /// too: it costs about as much memory as GPU and runs as slowly as the Neural Engine.
    private static func computeOptions(_ mode: ComputeMode) -> ModelComputeOptions {
        switch mode {
        case .fast:
            ModelComputeOptions(audioEncoderCompute: .cpuAndGPU, textDecoderCompute: .cpuAndGPU)
        case .efficient:
            ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine, textDecoderCompute: .cpuAndNeuralEngine)
        }
    }

    public enum EngineError: LocalizedError {
        case notReady

        public var errorDescription: String? {
            "The speech model is not loaded."
        }
    }
}
