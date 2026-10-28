public struct TranscriptionOptions: Sendable {
    public var languages: [SpokenLanguage]
    /// Context for the model: custom vocabulary and the previous utterance.
    public var prompt: String?

    public init(languages: [SpokenLanguage], prompt: String? = nil) {
        self.languages = languages
        self.prompt = prompt
    }
}

public struct Transcript: Sendable, Equatable {
    public var text: String
    public var language: SpokenLanguage?

    public init(text: String, language: SpokenLanguage?) {
        self.text = text
        self.language = language
    }
}

/// A speech-to-text backend (WhisperKit, whisper.cpp, Apple SpeechAnalyzer, ...).
public protocol TranscriptionEngine: Sendable {
    var isLoaded: Bool { get }
    /// Loads the model (downloading it first if needed).
    func prepare(compute: ComputeMode) async throws
    /// Frees the model's memory.
    func unload() async
    /// Requires a loaded model.
    /// - Parameter audio: 16 kHz mono Float32 samples.
    func transcribe(_ audio: [Float], options: TranscriptionOptions) async throws -> Transcript
}
