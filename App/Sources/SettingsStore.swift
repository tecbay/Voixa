import Foundation
import Observation
import VoixaKit

/// Persists `DictationSettings` in UserDefaults.
@MainActor
@Observable
final class SettingsStore {
    private static let key = "dictationSettings"

    var settings: DictationSettings {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(DictationSettings.self, from: data) {
            settings = saved
        } else {
            settings = DictationSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
