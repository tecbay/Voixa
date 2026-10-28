import Foundation
import os
import VoixaKit

/// Runs the `VoixaTranscriber` helper, which holds the speech model.
///
/// Ending the helper is how Voixa frees the model's memory: CoreML keeps
/// ~0.5 GB after an in-process unload, but nothing survives a process exit.
/// Requests are sent one at a time; `DictationController` serializes them.
@MainActor
final class TranscriberProcess {
    enum TranscriberError: LocalizedError {
        case helperMissing
        case helperExited
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .helperMissing: "Voixa's transcriber is missing from the app bundle."
            case .helperExited: "The transcriber stopped unexpectedly."
            case .failed(let message): message
            }
        }
    }

    private(set) var loadedMode: ComputeMode?
    var isRunning: Bool { process != nil }

    private var process: Process?
    private var input: FileHandle?
    private var readerTask: Task<Void, Never>?
    private var pending: CheckedContinuation<TranscriberResponse, Error>?
    private var onProgress: ((Double) -> Void)?
    private let log = Logger(subsystem: "com.techlevin.voixa.mac", category: "transcriber")

    /// Starts the helper if needed and loads `model`.
    func load(_ model: WhisperModel, mode: ComputeMode, onProgress: @escaping (Double) -> Void) async throws {
        try startIfNeeded()
        self.onProgress = onProgress
        defer { self.onProgress = nil }
        switch try await send(.load(model: model, mode: mode)) {
        case .loaded(let mode, let seconds):
            loadedMode = mode
            log.notice("helper loaded \(model.rawValue, privacy: .public) (\(mode.rawValue, privacy: .public)) in \(seconds, format: .fixed(precision: 1))s")
        case .failure(let message):
            throw TranscriberError.failed(message)
        default:
            throw TranscriberError.failed("Unexpected reply from the transcriber.")
        }
    }

    func transcribe(_ samples: [Float], options: TranscriptionOptions) async throws -> Transcript {
        let request = TranscriberRequest.transcribe(
            audio: TranscriberWire.audioData(samples),
            languages: options.languages,
            prompt: options.prompt
        )
        switch try await send(request) {
        case .transcript(let text, let language):
            return Transcript(text: text, language: language)
        case .failure(let message):
            throw TranscriberError.failed(message)
        default:
            throw TranscriberError.failed("Unexpected reply from the transcriber.")
        }
    }

    /// Ends the helper; all of the model's memory goes back to macOS.
    func stop() {
        guard let process else { return }
        try? input?.close()  // the helper exits when stdin closes
        process.terminate()
        cleanUp()
    }

    // MARK: - Process plumbing

    private func startIfNeeded() throws {
        guard process == nil else { return }
        guard let url = Bundle.main.url(forAuxiliaryExecutable: "VoixaTranscriber") else {
            throw TranscriberError.helperMissing
        }
        let process = Process()
        process.executableURL = url
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.terminationHandler = { [weak self] exited in
            let pid = exited.processIdentifier
            Task { @MainActor in self?.helperExited(pid: pid) }
        }
        try process.run()

        self.process = process
        input = stdin.fileHandleForWriting
        let output = stdout.fileHandleForReading
        readerTask = Task { [weak self] in
            do {
                for try await line in output.bytes.lines {
                    guard let response = TranscriberWire.decode(TranscriberResponse.self, from: line) else { continue }
                    self?.receive(response)
                }
            } catch {}
        }
        log.notice("helper started (pid \(process.processIdentifier))")
    }

    private func send(_ request: TranscriberRequest) async throws -> TranscriberResponse {
        guard let input else { throw TranscriberError.helperExited }
        let line = try TranscriberWire.line(request)
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            // Audio can be a few MB; write off the main thread.
            Task.detached {
                do {
                    try input.write(contentsOf: line)
                } catch {
                    await self.fail(error)
                }
            }
        }
    }

    private func receive(_ response: TranscriberResponse) {
        if case .progress(let fraction) = response {
            onProgress?(fraction)
            return
        }
        pending?.resume(returning: response)
        pending = nil
    }

    private func fail(_ error: Error) {
        pending?.resume(throwing: error)
        pending = nil
    }

    private func helperExited(pid: Int32) {
        // Ignore helpers we stopped ourselves.
        guard let process, process.processIdentifier == pid else { return }
        log.error("helper exited unexpectedly")
        fail(TranscriberError.helperExited)
        cleanUp()
    }

    private func cleanUp() {
        readerTask?.cancel()
        readerTask = nil
        input = nil
        process = nil
        loadedMode = nil
        fail(TranscriberError.helperExited)
    }
}
