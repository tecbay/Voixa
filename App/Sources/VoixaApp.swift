import SwiftUI
import VoixaKit

@main
struct VoixaApp: App {
    @State private var controller: DictationController

    init() {
        let controller = DictationController()
        controller.start()
        _controller = State(initialValue: controller)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            Image(systemName: controller.status.symbolName)
        }

        Window("Voixa Settings", id: "settings") {
            SettingsView(controller: controller)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

private struct MenuContent: View {
    let controller: DictationController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(controller.status.description(model: controller.model))
        if case .failed = controller.status {
            Button("Retry") { controller.loadModel() }
        }

        if controller.needsPermissions || controller.globeKeyConflicts {
            Button("⚠︎ Finish setup…") { controller.showSetup() }
        }

        Text(controller.memoryDescription)
        Divider()
        Text("Languages: " + controller.settings.settings.languages.map(\.displayName).joined(separator: ", "))
        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate()
        }
        .keyboardShortcut(",")
        Button("Quit Voixa") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

extension DictationController {
    var memoryDescription: String {
        switch loadedMode {
        case .fast: "Model in memory: fast mode (~2.5 GB, frees after 3 min idle)"
        case .efficient: "Model in memory: efficient mode (~0.3 GB, frees after 3 min idle)"
        case nil: "Model not in memory — loads when you press Fn"
        }
    }
}

extension DictationController.Status {
    var symbolName: String {
        switch self {
        case .downloading: "arrow.down.circle"
        case .loading: "hourglass"
        case .ready: "mic"
        case .recording: "mic.fill"
        case .transcribing: "waveform"
        case .failed: "exclamationmark.triangle"
        }
    }

    func description(model: WhisperModel) -> String {
        switch self {
        case .downloading(let fraction):
            "Downloading Whisper \(model.rawValue) (\(model.downloadSize))… \(Int(fraction * 100))%"
        case .loading:
            "Loading model… (first launch can take a few minutes)"
        case .ready:
            "Ready — hold Fn to dictate, double-tap for hands-free"
        case .recording:
            "Listening… (Esc to cancel)"
        case .transcribing:
            "Transcribing…"
        case .failed(let message):
            "Error: \(message)"
        }
    }
}
