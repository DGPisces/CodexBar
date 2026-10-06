import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageTurnPerformanceNativeProofTests {
    @Test
    func `production fetcher matches independently joined copied native history`() async throws {
        guard let directory = ProcessInfo.processInfo.environment["CODEXBAR_PERFORMANCE_NATIVE_PROOF_DIR"] else {
            return
        }
        let root = URL(
            fileURLWithPath: directory,
            isDirectory: true)
        let expected = try #require(JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent("expected.json"))) as? [[String: Any]])
        let now = try #require(CostUsageScanner.dateFromTimestamp("2026-10-06T23:59:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let options = CostUsageScanner.Options(
            codexSessionsRoot: root.appendingPathComponent("sessions"),
            cacheRoot: root.appendingPathComponent("cache"),
            codexTraceDatabaseURL: root.appendingPathComponent("missing-trace.sqlite"),
            calendar: calendar,
            maxCodexSessionFileBytes: 0,
            maxCodexScanBytesPerRefresh: 0,
            maxCodexScanDurationPerRefresh: 60)
        let started = ContinuousClock.now
        let fresh = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .codex,
            environment: [:],
            now: now,
            forceRefresh: true,
            historyDays: 30,
            allowPricingRefresh: false,
            includePiSessions: false,
            scannerOptions: options)
        let elapsed = (ContinuousClock.now - started).components
        let actual = fresh.sessions.flatMap(\.turnPerformanceSamples)
            .sorted { $0.completedAt < $1.completedAt }
        let reference = try expected.map { row in
            let timestamp = try #require(row["completed_at"] as? String)
            let completedAt = try #require(CostUsageScanner.dateFromTimestamp(timestamp))
            let outputTokens = try #require(row["output_tokens"] as? Int)
            let duration = try #require(row["duration_ms"] as? Int)
            return try #require(CostUsageTurnPerformanceSample(
                completedAt: completedAt,
                outputTokens: outputTokens,
                durationMilliseconds: duration,
                firstTokenMilliseconds: row["first_token_ms"] as? Int))
        }.sorted { $0.completedAt < $1.completedAt }
        #expect(actual == reference)
        let cached = try #require(await CostUsageFetcher.loadCachedCodexTokenSnapshot(
            now: now,
            historyDays: 30,
            includePiSessions: false,
            scannerOptions: options))
        #expect(cached.sessions.flatMap(\.turnPerformanceSamples).sorted {
            $0.completedAt < $1.completedAt
        } == actual)
        let receipt: [String: Any] = [
            "source": "copied native Codex JSONL, independent Python join",
            "expected_timed_turns": reference.count, "actual_timed_turns": actual.count,
            "fresh_matches_reference": actual == reference,
            "cached_matches_fresh": cached.sessions == fresh.sessions,
            "scan_wall_ms": Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15,
            "real_usage_values": "withheld",
        ]
        try JSONSerialization.data(
            withJSONObject: receipt,
            options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("receipt.json"))
    }
}
