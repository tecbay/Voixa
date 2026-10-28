import CoreGraphics

/// Watches the Fn (Globe) key system-wide with a listen-only event tap.
///
/// Needs Input Monitoring permission. Without it macOS still creates the tap
/// but only delivers keys typed while Voixa itself is focused, so callers must
/// check the permission rather than trusting `start()`.
@MainActor
final class HotkeyMonitor {
    enum Event {
        case fnDown, fnUp, otherKey, escape
    }

    var onEvent: ((Event) -> Void)?

    private var tap: CFMachPort?
    private var fnIsDown = false

    private static let functionKeyCode: Int64 = 63  // kVK_Function
    private static let escapeKeyCode: Int64 = 53    // kVK_Escape

    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        self.tap = nil
        fnIsDown = false
    }

    fileprivate func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }

        case .flagsChanged:
            guard keyCode == Self.functionKeyCode else { return }
            let down = flags.contains(.maskSecondaryFn)
            guard down != fnIsDown else { return }
            fnIsDown = down
            onEvent?(down ? .fnDown : .fnUp)

        case .keyDown:
            onEvent?(keyCode == Self.escapeKeyCode ? .escape : .otherKey)

        default:
            break
        }
    }
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let userInfo {
        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        // The tap's run loop source is on the main run loop.
        MainActor.assumeIsolated {
            monitor.handle(type: type, keyCode: keyCode, flags: flags)
        }
    }
    return Unmanaged.passUnretained(event)
}
