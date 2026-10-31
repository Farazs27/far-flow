import Foundation

public struct HardwareProfile: Sendable {
    public let memoryBytes: UInt64
    public init(memoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory) { self.memoryBytes=memoryBytes }
    public var automaticSummaries: Bool { memoryBytes >= 16*1024*1024*1024 }
    public var detail: String {
        automaticSummaries
        ? "Uses the standard local speech model and compact 4-bit writing model. Larger models are not needed."
        : "On this Mac, summaries start manually by default and the writing model is released after a meeting summary. Close memory-heavy apps before summarizing. The full meeting workflow is validated on 16 GB Macs."
    }
}
