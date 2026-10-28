import Foundation

/// Where downloaded models live. Shared by the app, the transcriber helper and
/// the command-line tool, so a model downloads once.
public enum ModelStore {
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Voixa/Models")
    }

    /// The folder WhisperKit's Hub client downloads a model into.
    public static func folder(for model: WhisperModel, in directory: URL = defaultDirectory) -> URL {
        directory
            .appending(path: "models/argmaxinc/whisperkit-coreml")
            .appending(path: model.whisperKitVariant)
    }

    public static func isDownloaded(_ model: WhisperModel, in directory: URL = defaultDirectory) -> Bool {
        FileManager.default.fileExists(atPath: completeMarker(model, in: directory).path)
    }

    /// Written only after a download finishes, so an interrupted download
    /// (folders present, weights missing) is resumed instead of loaded.
    public static func markDownloaded(_ model: WhisperModel, in directory: URL = defaultDirectory) {
        FileManager.default.createFile(atPath: completeMarker(model, in: directory).path, contents: nil)
    }

    private static func completeMarker(_ model: WhisperModel, in directory: URL) -> URL {
        folder(for: model, in: directory).appending(path: ".voixa-complete")
    }
}
