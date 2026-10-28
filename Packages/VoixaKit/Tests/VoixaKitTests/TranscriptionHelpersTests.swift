import Foundation
import Testing
@testable import VoixaKit

@Suite struct SpeechGateTests {
    @Test func rejectsShortClips() {
        #expect(!SpeechGate.containsSpeech([Float](repeating: 0.5, count: 1_000)))
    }

    @Test func rejectsSilence() {
        #expect(!SpeechGate.containsSpeech([Float](repeating: 0.001, count: 16_000)))
    }

    @Test func acceptsLoudAudio() {
        let tone = (0..<16_000).map { Float(sin(Double($0) * 0.1)) * 0.2 }
        #expect(SpeechGate.containsSpeech(tone))
    }
}

@Suite struct PromptBuilderTests {
    @Test func combinesVocabularyAndPreviousText() {
        let prompt = PromptBuilder.build(vocabulary: ["Laravel", " Voixa ", ""], previousText: "Deploy kar do.")
        #expect(prompt == "Laravel, Voixa. Deploy kar do.")
    }

    @Test func nilWhenNothingToSay() {
        #expect(PromptBuilder.build(vocabulary: [], previousText: "  ") == nil)
    }

    @Test func keepsMostRecentContext() {
        let long = String(repeating: "a", count: 1_000) + "END"
        let prompt = PromptBuilder.build(vocabulary: [], previousText: long)!
        #expect(prompt.count == PromptBuilder.maxCharacters)
        #expect(prompt.hasSuffix("END"))
    }
}
