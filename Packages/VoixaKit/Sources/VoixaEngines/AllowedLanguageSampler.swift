import CoreML
import VoixaKit
import WhisperKit

/// Language detection limited to the user's languages.
///
/// WhisperKit's `detectLanguage` only reports Whisper's top pick across all 99
/// languages. Accented English is often picked as Hindi, Urdu or Malay, and a
/// short Bengali clip as English. This sampler sees the same language logits
/// but only chooses among the allowed language tokens.
final class AllowedLanguageSampler: TokenSampling, @unchecked Sendable {
    private let candidates: [(token: Int, language: SpokenLanguage)]
    private(set) var chosen: SpokenLanguage?

    init?(allowed: [SpokenLanguage], tokenizer: any WhisperTokenizer) {
        candidates = allowed.compactMap { language in
            tokenizer.convertTokenToId("<|\(language.rawValue)|>").map { ($0, language) }
        }
        guard !candidates.isEmpty else { return nil }
    }

    func update(tokens: [Int], logits: MLMultiArray, logProbs: [Float]) async -> SamplingResult {
        // Logits are [1, 1, vocab], so the linear index is the token id.
        let best = candidates.max { logits[$0.token].floatValue < logits[$1.token].floatValue }!
        chosen = best.language
        if Debug.enabled {
            Debug.log("language logits: " + candidates.map { "\($0.language.rawValue)=\(logits[$0.token].floatValue)" }.joined(separator: " "))
        }
        return SamplingResult(tokens: tokens + [best.token], logProbs: logProbs + [0], completed: true)
    }

    func finalize(tokens: [Int], logProbs: [Float]) -> SamplingResult {
        SamplingResult(tokens: tokens, logProbs: logProbs, completed: true)
    }
}
