import Foundation
import VoixaEngines
import VoixaKit

let usage = """
usage: voixa-transcribe <audio-file> [--lang en,hi] [--model large-v3|large-v3-turbo] [--prompt TEXT] [--runs N]

Transcribes an audio file with the same engine and settings as the app.
"""

var arguments = Array(CommandLine.arguments.dropFirst())
var languages: [SpokenLanguage] = [.english]
var model = WhisperModel.default
var prompt: String?
var audioPath: String?
var runs = 1

while !arguments.isEmpty {
    let argument = arguments.removeFirst()
    switch argument {
    case "--lang":
        let codes = arguments.isEmpty ? "" : arguments.removeFirst()
        languages = codes.split(separator: ",").compactMap { SpokenLanguage(rawValue: String($0)) }
    case "--model":
        guard !arguments.isEmpty, let value = WhisperModel(rawValue: arguments.removeFirst()) else {
            print(usage)
            exit(1)
        }
        model = value
    case "--prompt":
        prompt = arguments.isEmpty ? nil : arguments.removeFirst()
    case "--runs":
        runs = arguments.isEmpty ? 1 : max(1, Int(arguments.removeFirst()) ?? 1)
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        audioPath = argument
    }
}

guard let audioPath, !languages.isEmpty else {
    print(usage)
    exit(1)
}

let modelName = model.rawValue
let engine = WhisperKitEngine(model: model) { fraction in
    FileHandle.standardError.write("\rDownloading \(modelName)… \(Int(fraction * 100))%".data(using: .utf8)!)
}

do {
    let audio = try WhisperKitEngine.loadAudio(path: audioPath)
    let loadStart = Date()
    let mode = ComputeMode.choose(availableMemory: SystemMemory.available())
    try await engine.prepare(compute: mode)
    let loadTime = Date().timeIntervalSince(loadStart)
    // Later runs show warm latency, which is what the app sees after the first dictation.
    var transcript = Transcript(text: "", language: nil)
    var elapsed: [TimeInterval] = []
    for _ in 0..<runs {
        let start = Date()
        transcript = try await engine.transcribe(audio, options: TranscriptionOptions(languages: languages, prompt: prompt))
        elapsed.append(Date().timeIntervalSince(start))
    }

    print(transcript.text)
    let audioSeconds = Double(audio.count) / 16_000
    FileHandle.standardError.write("""
    [model \(model.rawValue), mode \(mode.rawValue), language \(transcript.language?.rawValue ?? "auto"), \
    load \(String(format: "%.1f", loadTime))s, \
    audio \(String(format: "%.1f", audioSeconds))s, \
    transcribe \(elapsed.map { String(format: "%.2f", $0) }.joined(separator: " / "))s]

    """.data(using: .utf8)!)
} catch {
    FileHandle.standardError.write("error: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
