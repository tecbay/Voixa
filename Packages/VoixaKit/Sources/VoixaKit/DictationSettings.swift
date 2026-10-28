/// How non-English speech is written out.
public enum OutputScript: String, Codable, Sendable {
    /// Devanagari, Bengali, Nastaliq, ...
    case native
    /// Latin letters, e.g. "kya haal hai".
    case romanized
}

public struct DictationSettings: Codable, Equatable, Sendable {
    /// Languages the user speaks. Detection is limited to this set so accented
    /// English is not mistaken for another language.
    public var languages: [SpokenLanguage]
    public var outputScript: OutputScript
    /// Local LLM pass that fixes misheard words and punctuation. Opt-in.
    public var cleanupEnabled: Bool
    /// Names and terms passed to the model as context.
    public var customVocabulary: [String]
    public var model: WhisperModel

    public init(
        languages: [SpokenLanguage] = [.english],
        outputScript: OutputScript = .native,
        cleanupEnabled: Bool = false,
        customVocabulary: [String] = [],
        model: WhisperModel = .default
    ) {
        self.languages = languages
        self.outputScript = outputScript
        self.cleanupEnabled = cleanupEnabled
        self.customVocabulary = customVocabulary
        self.model = model
    }

    /// Fields missing from older saved settings fall back to defaults instead
    /// of discarding everything the user already chose.
    public init(from decoder: Decoder) throws {
        let defaults = DictationSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        languages = try container.decodeIfPresent([SpokenLanguage].self, forKey: .languages) ?? defaults.languages
        outputScript = try container.decodeIfPresent(OutputScript.self, forKey: .outputScript) ?? defaults.outputScript
        cleanupEnabled = try container.decodeIfPresent(Bool.self, forKey: .cleanupEnabled) ?? defaults.cleanupEnabled
        customVocabulary = try container.decodeIfPresent([String].self, forKey: .customVocabulary) ?? defaults.customVocabulary
        model = try container.decodeIfPresent(WhisperModel.self, forKey: .model) ?? defaults.model
    }

    /// Whisper writes Indic languages in native script, so romanized output
    /// can only be produced by the cleanup step.
    public var needsCleanupForScript: Bool {
        outputScript == .romanized && !cleanupEnabled
    }
}
