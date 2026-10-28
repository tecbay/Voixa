import Foundation
import Testing
@testable import VoixaKit

@Test func turboFitsEverywhere() {
    #expect(WhisperModel.largeV3Turbo.fitsInMemory(8 * 1024 * 1024 * 1024))
}

@Test func largeV3Needs16GB() {
    #expect(!WhisperModel.largeV3.fitsInMemory(8 * 1024 * 1024 * 1024))
    #expect(WhisperModel.largeV3.fitsInMemory(16 * 1024 * 1024 * 1024))
}

@Test func romanizedOutputNeedsCleanup() {
    var settings = DictationSettings(languages: [.english, .hindi], outputScript: .romanized)
    #expect(settings.needsCleanupForScript)
    settings.cleanupEnabled = true
    #expect(!settings.needsCleanupForScript)
}

@Test func defaultsMatchDecisions() {
    let settings = DictationSettings()
    #expect(settings.outputScript == .native)
    #expect(!settings.cleanupEnabled)
    #expect(settings.model == .largeV3Turbo)
}

@Test func olderSavedSettingsKeepUserChoices() throws {
    // Saved before the model setting existed.
    let json = #"{"languages":["en","bn"],"outputScript":"native","cleanupEnabled":false,"customVocabulary":["Laravel"]}"#
    let settings = try JSONDecoder().decode(DictationSettings.self, from: Data(json.utf8))
    #expect(settings.languages == [.english, .bengali])
    #expect(settings.customVocabulary == ["Laravel"])
    #expect(settings.model == .largeV3Turbo)
}

@Test func fastModeOnlyWithHeadroom() {
    let gb: UInt64 = 1024 * 1024 * 1024
    #expect(ComputeMode.choose(availableMemory: 12 * gb) == .fast)
    #expect(ComputeMode.choose(availableMemory: 4 * gb) == .fast)
    #expect(ComputeMode.choose(availableMemory: 3 * gb) == .efficient)
}

@Test func availableMemoryIsPlausible() {
    let available = SystemMemory.available()
    #expect(available > 0)
    #expect(available <= ProcessInfo.processInfo.physicalMemory)
}
