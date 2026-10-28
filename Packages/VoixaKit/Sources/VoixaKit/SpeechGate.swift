/// Cheap check that a recording contains speech before sending it to Whisper,
/// which tends to invent text ("Thank you for watching") on silence.
public enum SpeechGate {
    public static let sampleRate = 16_000
    public static let minimumDuration = 0.3
    /// RMS of the loudest 30 ms frame must exceed this.
    public static let minimumPeakRMS: Float = 0.01

    public static func containsSpeech(_ samples: [Float]) -> Bool {
        guard Double(samples.count) / Double(sampleRate) >= minimumDuration else { return false }
        return peakFrameRMS(samples) >= minimumPeakRMS
    }

    static func peakFrameRMS(_ samples: [Float], frameLength: Int = 480) -> Float {
        var peak: Float = 0
        var start = 0
        while start < samples.count {
            let end = min(start + frameLength, samples.count)
            var sum: Float = 0
            for i in start..<end { sum += samples[i] * samples[i] }
            peak = max(peak, (sum / Float(end - start)).squareRoot())
            start = end
        }
        return peak
    }
}
