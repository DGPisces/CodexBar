import Foundation
import Testing
@testable import CodexBarCore

/// Opt-in baseline comparison. All inputs are synthetic and never access account state.
@Suite(.serialized)
struct CostUsageTurnPerformanceBenchmarkTests {
    @Test
    func `measure cold warm incremental and persisted session projections`() throws {
        guard let output = ProcessInfo.processInfo.environment["CODEXBAR_TOKEN_SPEED_BENCHMARK_OUTPUT"] else { return }
        var results: [[String: Any]] = []
        for (name, files, turns, requests) in [("normal", 24, 40, 4), ("large", 96, 80, 6)] {
            for trial in 0..<3 {
                let env = try CostUsageTestEnvironment()
                defer { env.cleanup() }
                let day = try env.makeLocalNoon(
                    year: 2026,
                    month: 5,
                    day: 10)
                var urls: [URL] = []
                for file in 0..<files {
                    let id = "synthetic-speed-\(file)"
                    let prefix = try env.jsonl([[
                        "type": "session_meta",
                        "timestamp": env.isoString(for: day),
                        "payload": ["id": id],
                    ]])
                    let body = try (0..<turns).map {
                        try Self.turn(
                            env: env,
                            day: day,
                            session: id,
                            turn: $0,
                            requests: requests)
                    }.joined()
                    try urls.append(env.seedCodexSessionFile(
                        day: day,
                        filename: "speed-\(file).jsonl",
                        contents: prefix + body))
                }
                var options = CostUsageScanner.Options(
                    codexSessionsRoot: env.codexSessionsRoot,
                    cacheRoot: env.cacheRoot,
                    codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite"),
                    maxCodexSessionFileBytes: 0,
                    maxCodexScanBytesPerRefresh: 0,
                    maxCodexScanDurationPerRefresh: 60)
                options.refreshMinIntervalSeconds = 0
                let expected = files * turns * requests * 110
                var now = day
                for mode in ["cold", "warm", "warm", "warm", "append"] {
                    if mode == "append" {
                        let handle = try FileHandle(forWritingTo: urls[0])
                        try handle.seekToEnd()
                        try handle.write(contentsOf: Data(Self.turn(
                            env: env,
                            day: day,
                            session: "synthetic-speed-0",
                            turn: turns,
                            requests: requests).utf8))
                        try handle.close()
                    }
                    let recorder = CostUsageScanner.CodexScanWorkRecorder()
                    options.codexScanWorkRecorderForTesting = recorder
                    let start = ContinuousClock.now
                    let report = CostUsageScanner.loadDailyReport(
                        provider: .codex,
                        since: day,
                        until: day,
                        now: now,
                        options: options)
                    let scanMS = Self.milliseconds(since: start)
                    #expect(report.summary?.totalTokens == expected + (mode == "append" ? requests * 110 : 0))
                    let store = CostUsageStore(cacheRoot: env.cacheRoot)
                    let reloadStart = ContinuousClock.now
                    let cache = store.syncLoadCodexCache(calendar: options.calendar)
                    let range = CostUsageScanner.CostUsageDayRange(
                        since: day,
                        until: day,
                        calendar: options.calendar)
                    let sessions = CostUsageScanner.buildCodexSessionBreakdownsFromCache(
                        cache: cache,
                        range: range,
                        modelsDevCatalog: ModelsDevCatalog(providers: [:]))
                    let reloadMS = Self.milliseconds(since: reloadStart)
                    #expect(sessions.count == files)
                    let timedTurns = sessions.reduce(0) { $0 + $1.turnPerformanceSamples.count }
                    #expect(timedTurns == files * turns + (mode == "append" ? 1 : 0))
                    if mode == "warm" {
                        #expect(recorder.snapshot().usageRowsProcessed == 0)
                    }
                    let bytes = try (FileManager.default.contentsOfDirectory(
                        at: store.databaseURL.deletingLastPathComponent(),
                        includingPropertiesForKeys: [.fileSizeKey]))
                        .reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
                    results.append([
                        "corpus": name,
                        "trial": trial,
                        "mode": mode,
                        "files": files,
                        "turns": files * turns,
                        "requests": files * turns * requests,
                        "timed_turns": timedTurns,
                        "scan_ms": scanMS,
                        "reload_ms": reloadMS,
                        "cache_bytes": bytes,
                        "file_scans": recorder.snapshot().codexFileScanAttempts,
                        "usage_rows_processed": recorder.snapshot().usageRowsProcessed,
                    ])
                    now = now.addingTimeInterval(1)
                }
            }
        }
        let data = try JSONSerialization.data(
            withJSONObject: results,
            options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: output))
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = (ContinuousClock.now - start).components
        return Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
    }

    static func turn(
        env: CostUsageTestEnvironment,
        day: Date,
        session: String,
        turn: Int,
        requests: Int) throws -> String
    {
        let turnID = "turn-\(turn)"
        let start = day.addingTimeInterval(Double(turn * 30))
        var objects: [[String: Any]] = [[
            "type": "event_msg", "timestamp": env.isoString(for: start),
            "payload": ["type": "task_started", "turn_id": turnID],
        ]]
        for request in 0..<requests {
            let count = turn * requests + request + 1
            objects.append([
                "type": "token_usage_record",
                "timestamp": env.isoString(for: start.addingTimeInterval(Double(request))),
                "payload": [
                    "thread_id": session,
                    "session_id": session,
                    "turn_id": turnID,
                    "response_id": "\(session)-\(turn)-\(request)",
                    "model": "gpt-5.4",
                    "usage": Self.usage(1),
                    "thread_token_usage": Self.usage(count),
                    "turn_token_usage": Self.usage(request + 1),
                ],
            ])
        }
        objects.append([
            "type": "event_msg", "timestamp": env.isoString(for: start.addingTimeInterval(10)),
            "payload": [
                "type": "task_complete",
                "turn_id": turnID,
                "started_at": Int(start.timeIntervalSince1970),
                "completed_at": Int(start.timeIntervalSince1970) + 10,
                "duration_ms": 10000,
                "time_to_first_token_ms": 200,
                "error": NSNull(),
            ],
        ])
        return try env.jsonl(objects)
    }

    private static func usage(_ count: Int) -> [String: Int] {
        [
            "input_tokens": count * 100,
            "output_tokens": count * 10,
            "cached_input_tokens": 0,
            "reasoning_output_tokens": count * 5,
        ]
    }
}
