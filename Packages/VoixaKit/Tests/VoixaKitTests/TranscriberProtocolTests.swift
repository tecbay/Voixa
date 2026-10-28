import Foundation
import Testing
@testable import VoixaKit

@Suite struct TranscriberProtocolTests {
    @Test func requestRoundTrips() throws {
        let request = TranscriberRequest.transcribe(
            audio: TranscriberWire.audioData([0.5, -0.25]),
            languages: [.english, .hindi],
            prompt: "Laravel."
        )
        let line = String(decoding: try TranscriberWire.line(request), as: UTF8.self)
        #expect(line.hasSuffix("\n"))
        #expect(TranscriberWire.decode(TranscriberRequest.self, from: String(line.dropLast())) == request)
    }

    @Test func responseRoundTrips() throws {
        for response in [
            TranscriberResponse.progress(0.5),
            .loaded(mode: .fast, seconds: 1.2),
            .transcript(text: "नमस्ते", language: .hindi),
            .failure("boom"),
        ] {
            let line = String(decoding: try TranscriberWire.line(response), as: UTF8.self)
            #expect(TranscriberWire.decode(TranscriberResponse.self, from: String(line.dropLast())) == response)
        }
    }

    @Test func ignoresNonProtocolLines() {
        #expect(TranscriberWire.decode(TranscriberResponse.self, from: "[WhisperKit] some log line") == nil)
    }

    @Test func audioSurvivesEncoding() {
        let samples: [Float] = [0, 1, -1, 0.123]
        #expect(TranscriberWire.samples(from: TranscriberWire.audioData(samples)) == samples)
    }
}
