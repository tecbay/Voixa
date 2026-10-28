import Foundation

/// Turns raw Fn key events into dictation actions.
///
/// - Hold Fn: records while held, transcribes on release.
/// - Double-tap Fn: hands-free; records until Fn is pressed again.
/// - Fn used as a modifier (Fn+arrow, Fn+F-key): the recording is cancelled.
public struct PushToTalk: Sendable {
    public enum Event: Sendable {
        case fnDown(TimeInterval)
        case fnUp(TimeInterval)
        /// Any other key pressed.
        case otherKey
        case escape
    }

    public enum Action: Equatable, Sendable {
        case startRecording
        case stopAndTranscribe
        case cancelRecording
        /// Recording continues, now hands-free.
        case enterHandsFree
    }

    enum State: Equatable {
        case idle
        case holding(since: TimeInterval)
        case handsFree
        /// Fn went down to end hands-free mode; ignore its release.
        case awaitingRelease
    }

    /// Releases shorter than this count as a tap, not a hold.
    public var tapThreshold: TimeInterval = 0.3
    /// Max gap between two taps for a double-tap.
    public var doubleTapWindow: TimeInterval = 0.4

    private(set) var state: State = .idle
    private var lastTapEnd: TimeInterval?

    public init() {}

    public var isRecording: Bool {
        switch state {
        case .holding, .handsFree: true
        case .idle, .awaitingRelease: false
        }
    }

    public mutating func handle(_ event: Event) -> Action? {
        switch (state, event) {
        case (.idle, .fnDown(let time)):
            state = .holding(since: time)
            return .startRecording

        case (.holding(let since), .fnUp(let time)):
            let held = time - since
            if held >= tapThreshold {
                state = .idle
                lastTapEnd = nil
                return .stopAndTranscribe
            }
            if let lastTapEnd, since - lastTapEnd <= doubleTapWindow {
                state = .handsFree
                self.lastTapEnd = nil
                return .enterHandsFree
            }
            state = .idle
            lastTapEnd = time
            return .cancelRecording

        case (.holding, .otherKey), (.holding, .escape), (.handsFree, .escape):
            state = .idle
            lastTapEnd = nil
            return .cancelRecording

        case (.handsFree, .fnDown):
            state = .awaitingRelease
            return .stopAndTranscribe

        case (.awaitingRelease, .fnUp):
            state = .idle
            return nil

        default:
            return nil
        }
    }
}
