import Testing
@testable import VoixaKit

@Suite struct PushToTalkTests {
    @Test func holdRecordsAndTranscribesOnRelease() {
        var ptt = PushToTalk()
        #expect(ptt.handle(.fnDown(0)) == .startRecording)
        #expect(ptt.isRecording)
        #expect(ptt.handle(.fnUp(1.5)) == .stopAndTranscribe)
        #expect(!ptt.isRecording)
    }

    @Test func singleTapCancels() {
        var ptt = PushToTalk()
        _ = ptt.handle(.fnDown(0))
        #expect(ptt.handle(.fnUp(0.1)) == .cancelRecording)
    }

    @Test func doubleTapEntersHandsFreeAndNextPressStops() {
        var ptt = PushToTalk()
        _ = ptt.handle(.fnDown(0))
        _ = ptt.handle(.fnUp(0.1))
        #expect(ptt.handle(.fnDown(0.3)) == .startRecording)
        #expect(ptt.handle(.fnUp(0.4)) == .enterHandsFree)
        #expect(ptt.isRecording)
        #expect(ptt.handle(.otherKey) == nil)
        #expect(ptt.handle(.fnDown(5)) == .stopAndTranscribe)
        #expect(ptt.handle(.fnUp(5.1)) == nil)
        #expect(ptt.handle(.fnDown(6)) == .startRecording)
    }

    @Test func slowSecondTapIsNotDoubleTap() {
        var ptt = PushToTalk()
        _ = ptt.handle(.fnDown(0))
        _ = ptt.handle(.fnUp(0.1))
        _ = ptt.handle(.fnDown(1.0))
        #expect(ptt.handle(.fnUp(1.1)) == .cancelRecording)
    }

    @Test func fnAsModifierCancels() {
        var ptt = PushToTalk()
        _ = ptt.handle(.fnDown(0))
        #expect(ptt.handle(.otherKey) == .cancelRecording)
        #expect(ptt.handle(.fnUp(1)) == nil)
    }

    @Test func escapeCancelsHandsFree() {
        var ptt = PushToTalk()
        _ = ptt.handle(.fnDown(0))
        _ = ptt.handle(.fnUp(0.1))
        _ = ptt.handle(.fnDown(0.2))
        _ = ptt.handle(.fnUp(0.3))
        #expect(ptt.handle(.escape) == .cancelRecording)
        #expect(!ptt.isRecording)
    }
}
