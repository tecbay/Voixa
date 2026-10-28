import Darwin

/// Where the speech model runs. Measured with large-v3-turbo on an M3 Max,
/// 4.6 s Hinglish sentence:
///
/// | Mode      | Memory  | Transcribe |
/// |-----------|---------|------------|
/// | fast      | 2.5 GB  | 0.8 s      |
/// | efficient | 0.3 GB  | 1.6 s      |
public enum ComputeMode: String, Codable, Sendable {
    /// GPU: twice as fast, but the weights live in Voixa's memory.
    case fast
    /// Neural Engine: weights are managed by macOS outside Voixa's memory.
    case efficient

    /// Fast needs ~2.5 GB; keep headroom so loading it never pushes the Mac into swap.
    public static let fastModeMinimumAvailable: UInt64 = 4 * 1024 * 1024 * 1024

    public static func choose(availableMemory: UInt64) -> ComputeMode {
        availableMemory >= fastModeMinimumAvailable ? .fast : .efficient
    }
}

public enum SystemMemory {
    /// Memory macOS can hand out without swapping: free pages plus pages it
    /// can drop (inactive, purgeable, speculative).
    public static func available() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let pages = UInt64(stats.free_count) + UInt64(stats.inactive_count)
            + UInt64(stats.purgeable_count) + UInt64(stats.speculative_count)
        return pages * UInt64(getpagesize())
    }
}
