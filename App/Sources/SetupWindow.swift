import AppKit
import SwiftUI

/// Lists the permissions and settings Voixa needs, with live status.
/// Opened automatically at launch while anything is missing.
@MainActor
final class SetupWindow {
    private var window: NSWindow?

    func show(controller: DictationController) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SetupView(controller: controller) { [weak self] in
                self?.window?.close()
            }))
            window.title = "Set up Voixa"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

private struct SetupView: View {
    let controller: DictationController
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Voixa types what you say into any app. It needs a few permissions; everything stays on this Mac.")
                .fixedSize(horizontal: false, vertical: true)

            step(
                done: controller.microphoneGranted,
                title: "Microphone",
                detail: "To hear you while you hold Fn.",
                action: Permissions.openMicrophoneSettings
            )
            step(
                done: controller.inputMonitoringGranted,
                title: "Input Monitoring",
                detail: "To notice the Fn key while you're in other apps.",
                action: Permissions.openInputMonitoringSettings
            )
            step(
                done: controller.accessibilityGranted,
                title: "Accessibility",
                detail: "To paste the text into the field you're typing in.",
                action: Permissions.openAccessibilitySettings
            )
            step(
                done: !controller.globeKeyConflicts,
                title: "Globe key: Do Nothing",
                detail: "Keyboard settings → “Press 🌐 key to” → Do Nothing, so macOS doesn't also react to Fn.",
                action: GlobeKeySetting.openKeyboardSettings
            )

            Divider()
            HStack {
                Text(controller.needsPermissions || controller.globeKeyConflicts
                     ? "If a switch is already on but not ticked here, turn it off and on again."
                     : "All set. Click into any text box, hold Fn and speak.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Done", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func step(done: Bool, title: String, detail: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(done ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !done {
                Button("Open Settings", action: action)
            }
        }
    }
}
