import AppKit

/// Types text into the focused field of any app by pasting it, then puts the
/// user's clipboard back. Pasting works in far more apps (Electron, browsers,
/// terminals) than the Accessibility text APIs. Needs Accessibility permission.
@MainActor
enum TextInserter {
    /// Tells clipboard managers to ignore our temporary clipboard entry.
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    enum Result {
        case pasted
        /// No Accessibility permission, so the text was left on the clipboard.
        case copiedOnly
    }

    @discardableResult
    static func insert(_ text: String) async -> Result {
        let pasteboard = NSPasteboard.general
        guard AXIsProcessTrusted() else {
            // macOS silently drops synthetic ⌘V without Accessibility access.
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return .copiedOnly
        }
        let saved = snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: transientType)
        let ourChangeCount = pasteboard.changeCount

        postCommandV()

        // Give the target app time to read the clipboard before restoring it.
        try? await Task.sleep(for: .milliseconds(300))
        guard pasteboard.changeCount == ourChangeCount else { return .pasted }  // something else copied meanwhile
        restore(saved, to: pasteboard)
        return .pasted
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9  // kVK_ANSI_V
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { contents[type] = data }
            }
            return contents
        }
    }

    private static func restore(_ saved: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !saved.isEmpty else { return }
        let items = saved.map { contents in
            let item = NSPasteboardItem()
            for (type, data) in contents { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
