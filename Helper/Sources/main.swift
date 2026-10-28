import Foundation
import VoixaEngines
import VoixaKit

// VoixaTranscriber: runs the speech model on behalf of the Voixa app.
//
// The app starts this process when dictation needs the model and ends it when
// idle, which is the only way to give all of CoreML's memory back to macOS.
// It reads `TranscriberRequest` lines on stdin, answers with
// `TranscriberResponse` lines on stdout, and exits when stdin closes.

func send(_ response: TranscriberResponse) {
    if let line = try? TranscriberWire.line(response) {
        FileHandle.standardOutput.write(line)
    }
}

var engine: WhisperKitEngine?

for try await line in FileHandle.standardInput.bytes.lines {
    guard let request = TranscriberWire.decode(TranscriberRequest.self, from: line) else { continue }

    switch request {
    case .load(let model, let mode):
        if engine?.model != model {
            await engine?.unload()
            engine = WhisperKitEngine(model: model) { send(.progress($0)) }
        }
        let start = Date()
        do {
            try await engine?.prepare(compute: mode)
            send(.loaded(mode: mode, seconds: Date().timeIntervalSince(start)))
        } catch {
            send(.failure(error.localizedDescription))
        }

    case .transcribe(let audio, let languages, let prompt):
        guard let engine, engine.isLoaded else {
            send(.failure("The speech model is not loaded."))
            continue
        }
        do {
            let transcript = try await engine.transcribe(
                TranscriberWire.samples(from: audio),
                options: TranscriptionOptions(languages: languages, prompt: prompt)
            )
            send(.transcript(text: transcript.text, language: transcript.language))
        } catch {
            send(.failure(error.localizedDescription))
        }
    }
}
