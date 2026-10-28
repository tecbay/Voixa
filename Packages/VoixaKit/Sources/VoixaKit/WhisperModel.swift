import Foundation

public enum WhisperModel: String, CaseIterable, Codable, Sendable {
    case largeV3Turbo = "large-v3-turbo"
    case largeV3 = "large-v3"

    /// Turbo matched large-v3 on Hindi, Hinglish and Indian English in the
    /// first benchmark and is about 3x faster (see docs/DECISIONS.md).
    public static let `default` = WhisperModel.largeV3Turbo

    /// Full large-v3 needs the memory headroom of a 16 GB Mac.
    public func fitsInMemory(
        _ physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> Bool {
        switch self {
        case .largeV3Turbo: true
        case .largeV3: physicalMemory >= 16 * 1024 * 1024 * 1024
        }
    }

    public var displayName: String {
        switch self {
        case .largeV3Turbo: "Whisper large-v3-turbo (fast)"
        case .largeV3: "Whisper large-v3 (slower, may be more accurate)"
        }
    }

    /// Folder name in the argmaxinc/whisperkit-coreml repo. Both are the
    /// uncompressed variants; the compressed ones lose quality on Indic languages.
    public var whisperKitVariant: String {
        switch self {
        case .largeV3: "openai_whisper-large-v3"
        case .largeV3Turbo: "openai_whisper-large-v3-v20240930"
        }
    }

    /// Approximate download size, for the UI.
    public var downloadSize: String {
        switch self {
        case .largeV3: "3 GB"
        case .largeV3Turbo: "1.6 GB"
        }
    }
}
