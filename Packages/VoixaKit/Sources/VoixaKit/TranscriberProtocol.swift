import Foundation

/// Messages between the app and the `VoixaTranscriber` helper process.
///
/// The model runs in the helper so the app can quit it when idle: CoreML keeps
/// ~0.5 GB of buffers after a model is unloaded, and only ending the process
/// gives that memory back. Messages are JSON lines on stdin/stdout, prefixed
/// so stray library output on stdout is ignored.
public enum TranscriberRequest: Codable, Sendable, Equatable {
    case load(model: WhisperModel, mode: ComputeMode)
    /// `audio` is 16 kHz mono Float32, little-endian (see `TranscriberWire.audioData`).
    case transcribe(audio: Data, languages: [SpokenLanguage], prompt: String?)
}

public enum TranscriberResponse: Codable, Sendable, Equatable {
    case progress(Double)
    case loaded(mode: ComputeMode, seconds: Double)
    case transcript(text: String, language: SpokenLanguage?)
    case failure(String)
}

public enum TranscriberWire {
    static let prefix = "@voixa "

    public static func line<T: Encodable>(_ message: T) throws -> Data {
        var data = Data(prefix.utf8)
        data.append(try JSONEncoder().encode(message))
        data.append(0x0A)
        return data
    }

    /// Nil for lines that aren't protocol messages.
    public static func decode<T: Decodable>(_ type: T.Type, from line: String) -> T? {
        guard line.hasPrefix(prefix) else { return nil }
        return try? JSONDecoder().decode(type, from: Data(line.dropFirst(prefix.count).utf8))
    }

    public static func audioData(_ samples: [Float]) -> Data {
        samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    public static func samples(from data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
