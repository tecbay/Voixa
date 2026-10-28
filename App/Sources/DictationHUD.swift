import AppKit
import Observation
import SwiftUI

/// A small pill at the bottom of the screen showing what Voixa is doing.
/// It is a non-activating panel, so the text field you're dictating into
/// keeps keyboard focus.
@MainActor
final class DictationHUD {
    enum Mode: Equatable {
        case listening(handsFree: Bool)
        case transcribing
        case message(String, symbol: String)
    }

    @Observable
    final class Model {
        var mode: Mode = .transcribing
    }

    private let model = Model()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ mode: Mode) {
        hideTask?.cancel()
        model.mode = mode
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
    }

    /// Shows a message, then hides.
    func flash(_ text: String, symbol: String, for duration: Duration = .seconds(2)) {
        show(.message(text, symbol: symbol))
        hide(after: duration)
    }

    func hide(after delay: Duration = .zero) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        return panel
    }

    /// Bottom centre of the screen the user is working on.
    private func position(_ panel: NSPanel) {
        let size = NSSize(width: 340, height: 56)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrame(
            NSRect(x: frame.midX - size.width / 2, y: frame.minY + 48, width: size.width, height: size.height),
            display: true
        )
    }
}

private struct HUDView: View {
    let model: DictationHUD.Model

    var body: some View {
        HStack(spacing: 10) {
            icon
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var icon: some View {
        switch model.mode {
        case .listening:
            Image(systemName: "mic.fill")
                .foregroundStyle(.red)
                .symbolEffect(.pulse, options: .repeating)
        case .transcribing:
            ProgressView().controlSize(.small)
        case .message(_, let symbol):
            Image(systemName: symbol)
        }
    }

    private var text: String {
        switch model.mode {
        case .listening(handsFree: false): "Listening… release Fn to finish"
        case .listening(handsFree: true): "Listening… press Fn to finish, Esc to cancel"
        case .transcribing: "Transcribing…"
        case .message(let text, _): text
        }
    }
}
