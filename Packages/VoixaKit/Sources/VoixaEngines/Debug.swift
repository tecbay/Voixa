import CoreML
import Foundation
import WhisperKit

/// Diagnostic output on stderr, enabled with `VOIXA_DEBUG=1`.
enum Debug {
    static let enabled = ProcessInfo.processInfo.environment["VOIXA_DEBUG"] == "1"

    /// `VOIXA_COMPUTE=ane|gpu|mixed` (mixed: Neural Engine encoder, GPU decoder),
    /// for benchmarking on other Macs.
    static var computeOverride: ModelComputeOptions? {
        let units: (MLComputeUnits, MLComputeUnits)
        switch ProcessInfo.processInfo.environment["VOIXA_COMPUTE"] {
        case "ane": units = (.cpuAndNeuralEngine, .cpuAndNeuralEngine)
        case "gpu": units = (.cpuAndGPU, .cpuAndGPU)
        case "mixed": units = (.cpuAndNeuralEngine, .cpuAndGPU)
        default: return nil
        }
        return ModelComputeOptions(audioEncoderCompute: units.0, textDecoderCompute: units.1)
    }

    static func log(_ message: String) {
        FileHandle.standardError.write(("[voixa] " + message + "\n").data(using: .utf8)!)
    }
}
