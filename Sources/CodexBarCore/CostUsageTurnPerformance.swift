import Foundation

/// A successfully completed Codex turn, including reasoning tokens and tool/wait time.
/// This cannot be interpreted as the model's streaming generation throughput.
public struct CostUsageTurnPerformanceSample: Sendable, Equatable {
    public let completedAt: Date
    public let outputTokens: Int
    public let durationMilliseconds: Int
    public let firstTokenMilliseconds: Int?

    public init?(
        completedAt: Date,
        outputTokens: Int,
        durationMilliseconds: Int,
        firstTokenMilliseconds: Int? = nil)
    {
        guard completedAt.timeIntervalSince1970.isFinite, outputTokens >= 0,
              durationMilliseconds > 0 else { return nil }
        self.completedAt = completedAt
        self.outputTokens = outputTokens
        self.durationMilliseconds = durationMilliseconds
        self.firstTokenMilliseconds = firstTokenMilliseconds.flatMap {
            (0...durationMilliseconds).contains($0) ? $0 : nil
        }
    }
}

/// Throughput is weighted by elapsed time; TTFT is the median of the available observations.
public struct CostUsageTurnPerformanceSummary: Sendable, Equatable {
    public let sampleCount: Int
    public let outputTokensPerSecond: Double
    public let medianFirstTokenMilliseconds: Double?
    public let firstTokenSampleCount: Int

    public init?(samples: [CostUsageTurnPerformanceSample]) {
        guard !samples.isEmpty,
              let output = CheckedSum.integers(samples.map(\.outputTokens)),
              let duration = CheckedSum.integers(samples.map(\.durationMilliseconds)),
              duration > 0
        else { return nil }
        self.sampleCount = samples.count
        self.outputTokensPerSecond = Double(output) / Double(duration) * 1000
        let firstTokens = samples.compactMap(\.firstTokenMilliseconds).sorted()
        self.firstTokenSampleCount = firstTokens.count
        let middle = firstTokens.count / 2
        self.medianFirstTokenMilliseconds = if firstTokens.isEmpty {
            nil
        } else if firstTokens.count.isMultiple(of: 2) {
            Double(firstTokens[middle - 1]) / 2 + Double(firstTokens[middle]) / 2
        } else {
            Double(firstTokens[middle])
        }
    }
}
