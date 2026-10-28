import Foundation

/// Builds the text prompt Whisper is conditioned on. Vocabulary helps it spell
/// names and technical terms; the previous utterance keeps style and
/// code-switching consistent.
public enum PromptBuilder {
    /// Whisper's prompt window is 224 tokens; stay well inside it.
    public static let maxCharacters = 600

    public static func build(vocabulary: [String], previousText: String?) -> String? {
        let terms = vocabulary
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var parts: [String] = []
        if !terms.isEmpty {
            parts.append(terms.joined(separator: ", ") + ".")
        }
        if let previousText {
            let trimmed = previousText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append(trimmed) }
        }
        guard !parts.isEmpty else { return nil }
        // Keep the end: the most recent context matters most.
        return String(parts.joined(separator: " ").suffix(maxCharacters))
    }
}
