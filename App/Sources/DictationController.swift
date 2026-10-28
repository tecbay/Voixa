import AppKit
import Observation
import os
import VoixaKit

/// Runs the dictation loop: Fn → record → transcribe → paste.
@MainActor
@Observable
final class DictationController {
    enum Status: Equatable {
        case downloading(Double)
        case loading
        case ready
        case recording
        case transcribing
        case failed(String)
    }

    private(set) var status: Status = .loading
    private(set) var microphoneGranted = Permissions.microphoneGranted
    private(set) var accessibilityGranted = Permissions.accessibilityGranted
    private(set) var inputMonitoringGranted = Permissions.inputMonitoringGranted
    private(set) var globeKeyConflicts = GlobeKeySetting.conflicts
    /// How the model is currently loaded; nil when it's not in memory.
    private(set) var loadedMode: ComputeMode?

    let settings = SettingsStore()

    var model: WhisperModel { settings.settings.model }

    private let recorder = AudioRecorder()
    private let hotkeys = HotkeyMonitor()
    private let hud = DictationHUD()
    private let setupWindow = SetupWindow()
    private let log = Logger(subsystem: "com.techlevin.voixa.mac", category: "dictation")
    private var pushToTalk = PushToTalk()
    private var permissionTimer: Timer?

    // Memory: the model lives in a helper process that is started on demand
    // and ended when idle, so Voixa itself stays small.
    private let transcriber = TranscriberProcess()
    private var loadTask: Task<Void, Error>?
    /// Bumped when switching models, so an old load can't update the new one's state.
    private var loadGeneration = 0
    private var idleUnloadTask: Task<Void, Never>?
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    /// Memory pressure arrived mid-dictation; unload as soon as it finishes.
    private var unloadWhenIdle = false
    /// How long the model stays in memory after the last dictation.
    /// `VOIXA_IDLE_SECONDS` overrides it for testing.
    private static let idleUnloadDelay: Duration = .seconds(
        Int(ProcessInfo.processInfo.environment["VOIXA_IDLE_SECONDS"] ?? "") ?? 180
    )

    /// Previous utterance, used as context if recent.
    private var lastText: String?
    private var lastTextTime: Date?
    private static let contextLifetime: TimeInterval = 120

    var needsPermissions: Bool {
        !microphoneGranted || !accessibilityGranted || !inputMonitoringGranted
    }

    func start() {
        hotkeys.onEvent = { [weak self] event in self?.handle(event) }

        Task {
            if Permissions.microphoneUndetermined {
                _ = await Permissions.requestMicrophone()
            }
            if !Permissions.accessibilityGranted {
                Permissions.requestAccessibility()
            }
            refreshPermissions()
        }
        if !Permissions.inputMonitoringGranted {
            Permissions.requestInputMonitoring()
        }
        _ = hotkeys.start()
        refreshPermissions()
        log.notice("started: mic=\(self.microphoneGranted) accessibility=\(self.accessibilityGranted) inputMonitoring=\(self.inputMonitoringGranted)")
        startPermissionPolling()
        watchMemoryPressure()
        loadModel()
        if needsPermissions || globeKeyConflicts {
            showSetup()
        }
    }

    func showSetup() {
        setupWindow.show(controller: self)
    }

    /// Switches to another model, downloading it if needed.
    func selectModel(_ newModel: WhisperModel) {
        guard newModel != model, status != .recording, status != .transcribing else { return }
        settings.settings.model = newModel
        loadGeneration += 1
        transcriber.stop()
        loadTask = nil
        loadedMode = nil
        loadModel()
    }

    /// Downloads (if needed) and loads the model. Used at launch, on retry and
    /// after switching models; loading once at launch also warms the CoreML
    /// compile cache so later on-demand loads take about a second.
    func loadModel() {
        if !model.fitsInMemory() {
            settings.settings.model = .default
        }
        let generation = loadGeneration
        status = ModelStore.isDownloaded(model) ? .loading : .downloading(0)
        Task {
            do {
                try await ensureLoaded()
                guard loadGeneration == generation else { return }
                status = .ready
                scheduleIdleUnload()
            } catch {
                guard loadGeneration == generation else { return }
                status = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Memory

    /// Loads the model if it isn't in memory, choosing GPU (fast) when the Mac
    /// has memory to spare and the Neural Engine (efficient) otherwise.
    /// Concurrent callers share one load.
    private func ensureLoaded() async throws {
        if transcriber.loadedMode != nil { return }
        if let loadTask { return try await loadTask.value }

        let available = SystemMemory.available()
        let mode = ComputeMode.choose(availableMemory: available)
        let model = self.model
        let generation = loadGeneration
        let task = Task {
            try await transcriber.load(model, mode: mode) { [weak self] fraction in
                // Progress only arrives while downloading.
                guard let self, self.loadGeneration == generation else { return }
                self.status = fraction < 1 ? .downloading(fraction) : .loading
            }
        }
        loadTask = task
        defer {
            if loadGeneration == generation { loadTask = nil }
        }
        try await task.value
        guard loadGeneration == generation else { return }
        loadedMode = mode
        log.notice("model loaded: \(mode.rawValue, privacy: .public), \(available / 1_048_576) MB were available")
    }

    private func scheduleIdleUnload() {
        idleUnloadTask?.cancel()
        if unloadWhenIdle {
            unloadWhenIdle = false
            unloadModel(reason: "memory pressure")
            return
        }
        idleUnloadTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleUnloadDelay)
            guard !Task.isCancelled else { return }
            self?.unloadModel(reason: "idle")
        }
    }

    /// Ends the transcriber process, returning all of the model's memory.
    private func unloadModel(reason: String) {
        guard status == .ready, loadTask == nil, transcriber.isRunning else { return }
        transcriber.stop()
        loadedMode = nil
        log.notice("model unloaded: \(reason, privacy: .public)")
    }

    private func watchMemoryPressure() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.status == .ready {
                    self.unloadModel(reason: "memory pressure")
                } else {
                    self.unloadWhenIdle = true
                }
            }
        }
        source.resume()
        memoryPressureSource = source
    }

    // MARK: - Permissions

    func refreshPermissions() {
        microphoneGranted = Permissions.microphoneGranted
        accessibilityGranted = Permissions.accessibilityGranted
        globeKeyConflicts = GlobeKeySetting.conflicts

        let granted = Permissions.inputMonitoringGranted
        if granted && !inputMonitoringGranted {
            // A tap created before the grant only sees Voixa's own keys; recreate it.
            log.notice("input monitoring granted, restarting hotkey tap")
            hotkeys.stop()
        }
        inputMonitoringGranted = granted
        if !hotkeys.isRunning {
            _ = hotkeys.start()
        }
    }

    /// macOS has no callback for permission changes, so poll while something is missing.
    private func startPermissionPolling() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshPermissions()
            }
        }
    }

    // MARK: - Dictation

    private func handle(_ event: HotkeyMonitor.Event) {
        let now = ProcessInfo.processInfo.systemUptime
        let pttEvent: PushToTalk.Event = switch event {
        case .fnDown: .fnDown(now)
        case .fnUp: .fnUp(now)
        case .otherKey: .otherKey
        case .escape: .escape
        }
        guard let action = pushToTalk.handle(pttEvent) else { return }

        switch action {
        case .startRecording:
            startRecording()
        case .enterHandsFree:
            guard recorder.isRecording else { return }
            hud.show(.listening(handsFree: true))
        case .cancelRecording:
            guard recorder.isRecording else { return }
            _ = recorder.stop()
            status = .ready
            hud.hide()
            scheduleIdleUnload()
        case .stopAndTranscribe:
            guard recorder.isRecording else { return }
            transcribe(recorder.stop())
        }
    }

    private func startRecording() {
        guard microphoneGranted else {
            hud.flash("Voixa needs microphone access — see the menu bar icon", symbol: "mic.slash")
            return
        }
        switch status {
        case .ready:
            break
        case .downloading, .loading:
            hud.flash("Speech model is still loading…", symbol: "hourglass")
            return
        case .failed:
            hud.flash("Speech model failed to load — see the menu bar icon", symbol: "exclamationmark.triangle")
            return
        case .recording, .transcribing:
            return
        }
        do {
            try recorder.start()
            status = .recording
            hud.show(.listening(handsFree: false))
            idleUnloadTask?.cancel()
            // Load while the user is still speaking, so it rarely adds delay.
            if loadedMode == nil {
                Task { try? await ensureLoaded() }
            }
        } catch {
            log.error("recording failed: \(error.localizedDescription)")
            hud.flash(error.localizedDescription, symbol: "exclamationmark.triangle")
        }
    }

    private func transcribe(_ samples: [Float]) {
        guard SpeechGate.containsSpeech(samples) else {
            status = .ready
            hud.flash("Didn't hear anything", symbol: "ear")
            scheduleIdleUnload()
            return
        }
        status = .transcribing
        hud.show(.transcribing)

        let current = settings.settings
        let options = TranscriptionOptions(
            languages: current.languages,
            prompt: PromptBuilder.build(vocabulary: current.customVocabulary, previousText: recentContext)
        )

        Task {
            defer { scheduleIdleUnload() }
            do {
                try await ensureLoaded()
                let transcript = try await transcriber.transcribe(samples, options: options)
                status = .ready
                guard !transcript.text.isEmpty else {
                    hud.flash("Didn't catch that", symbol: "ear")
                    return
                }
                lastText = transcript.text
                lastTextTime = Date()
                switch await TextInserter.insert(transcript.text) {
                case .pasted:
                    hud.hide()
                case .copiedOnly:
                    hud.flash("Copied — press ⌘V to paste. Grant Accessibility to paste automatically.", symbol: "doc.on.clipboard", for: .seconds(4))
                }
                log.notice("transcribed \(samples.count / 16_000)s, language \(transcript.language?.rawValue ?? "auto", privacy: .public)")
            } catch {
                // One failed transcription shouldn't block the next one.
                status = .ready
                loadedMode = transcriber.loadedMode  // nil if the helper crashed
                log.error("transcription failed: \(error.localizedDescription)")
                hud.flash("Transcription failed: \(error.localizedDescription)", symbol: "exclamationmark.triangle", for: .seconds(3))
            }
        }
    }

    private var recentContext: String? {
        guard let lastTextTime, Date().timeIntervalSince(lastTextTime) < Self.contextLifetime else { return nil }
        return lastText
    }
}
