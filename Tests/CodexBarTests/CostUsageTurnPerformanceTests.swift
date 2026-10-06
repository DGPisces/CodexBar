import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageTurnPerformanceTests {
    @Test
    func `completed turns use deduplicated output and survive reopening the cache`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(
            year: 2026,
            month: 5,
            day: 10)
        let objects = try Self.objects(
            env: env,
            day: day)
        _ = try Self.write(
            env: env,
            day: day,
            objects: objects + Array(objects.suffix(3)))
        let first = Self.samples(
            env: env,
            day: day)
        let sample = try #require(first.first)
        #expect(first.count == 1)
        #expect(sample.outputTokens == 20)
        #expect(sample.durationMilliseconds == 10000)
        #expect(sample.firstTokenMilliseconds == 200)
        let summary = try #require(CostUsageTurnPerformanceSummary(samples: first))
        #expect(summary.outputTokensPerSecond == 2)
        for _ in 0..<25 {
            let recorder = CostUsageScanner.CodexScanWorkRecorder()
            #expect(Self.samples(
                env: env,
                day: day,
                recorder: recorder) == first)
            #expect(recorder.snapshot().usageRowsProcessed == 0)
        }
    }

    @Test
    func `legacy mirrors do not inflate timed output`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(
            year: 2026,
            month: 5,
            day: 10)
        let objects = try Self.objects(
            env: env,
            day: day)
        var mirrored: [[String: Any]] = []
        for object in objects {
            mirrored.append(object)
            if object["type"] as? String == "token_usage_record",
               let payload = object["payload"] as? [String: Any]
            {
                try mirrored.append([
                    "type": "event_msg", "timestamp": #require(object["timestamp"]),
                    "payload": ["type": "token_count", "turn_id": "turn-0", "info": [
                        "last_token_usage": #require(payload["usage"]),
                        "total_token_usage": #require(payload["thread_token_usage"]),
                    ]],
                ])
            }
        }
        _ = try Self.write(
            env: env,
            day: day,
            objects: mirrored)
        #expect(Self.samples(
            env: env,
            day: day).first?.outputTokens == 20)
    }

    @Test(arguments: ["0", "-1", "true", "0.5", "\"10000\"", "9223372036854775807"])
    func `invalid durations do not create a sample`(_ json: String) throws {
        try Self.withFixture { env, day, objects in
            var changed = objects
            var payload = try #require(changed.last?["payload"] as? [String: Any])
            payload["duration_ms"] = try JSONSerialization.jsonObject(
                with: Data(json.utf8),
                options: [.fragmentsAllowed])
            changed[changed.count - 1]["payload"] = payload
            _ = try Self.write(
                env: env,
                day: day,
                objects: changed)
            #expect(Self.samples(
                env: env,
                day: day).isEmpty)
        }
    }

    @Test
    func `failed or unfinished turns retain usage without reporting speed`() throws {
        try Self.withFixture { env, day, objects in
            let url = try Self.write(
                env: env,
                day: day,
                objects: Array(objects.dropLast()))
            #expect(Self.samples(
                env: env,
                day: day).isEmpty)
            var failure = try #require(objects.last)
            var payload = try #require(failure["payload"] as? [String: Any])
            payload["error"] = ["message": "synthetic failure"]
            failure["payload"] = payload
            try Self.append(
                [failure],
                to: url,
                env: env)
            #expect(Self.samples(
                env: env,
                day: day).isEmpty)
            try Self.append(
                [#require(objects.last)],
                to: url,
                env: env)
            #expect(Self.samples(
                env: env,
                day: day).count == 1)
            try Self.append(
                [failure],
                to: url,
                env: env)
            #expect(Self.samples(
                env: env,
                day: day).isEmpty)
        }
    }

    @Test
    func `completion appended after a scan uses persisted request totals`() throws {
        try Self.withFixture { env, day, objects in
            let url = try Self.write(
                env: env,
                day: day,
                objects: Array(objects.dropLast()))
            #expect(Self.samples(
                env: env,
                day: day).isEmpty)
            try Self.append(
                [#require(objects.last)],
                to: url,
                env: env)
            #expect(Self.samples(
                env: env,
                day: day).first?.outputTokens == 20)
        }
    }

    @Test(arguments: ["true", "-1", "10001", "0.5", "\"200\"", "null"])
    func `invalid first token timing leaves whole turn speed available`(_ json: String) throws {
        try Self.withFixture { env, day, objects in
            var changed = objects
            var payload = try #require(changed.last?["payload"] as? [String: Any])
            payload["time_to_first_token_ms"] = try JSONSerialization.jsonObject(
                with: Data(json.utf8),
                options: [.fragmentsAllowed])
            changed[changed.count - 1]["payload"] = payload
            _ = try Self.write(
                env: env,
                day: day,
                objects: changed)
            let sample = try #require(Self.samples(
                env: env,
                day: day).first)
            #expect(sample.firstTokenMilliseconds == nil)
            #expect(sample.outputTokens == 20)
        }
    }

    @Test
    func `a time budget eventually discovers completion appended after a cached refresh`() throws {
        try Self.withFixture { env, day, objects in
            let url = try Self.write(
                env: env,
                day: day,
                objects: Array(objects.dropLast()))
            #expect(Self.samples(
                env: env,
                day: day,
                durationLimit: 2).isEmpty)
            try Self.append(
                [#require(objects.last)],
                to: url,
                env: env)
            var observed: [CostUsageTurnPerformanceSample] = []
            for _ in 0..<4 {
                observed = Self.samples(
                    env: env,
                    day: day,
                    durationLimit: 2)
                if !observed.isEmpty { break }
            }
            #expect(observed.first?.outputTokens == 20)
        }
    }

    @Test
    func `copied foreign requests and incomplete turn totals cannot produce speed`() throws {
        try Self.withFixture { env, day, objects in
            var changed = objects
            for index in changed.indices where changed[index]["type"] as? String == "token_usage_record" {
                var payload = try #require(changed[index]["payload"] as? [String: Any])
                payload["thread_id"] = "foreign-parent"
                changed[index]["payload"] = payload
            }
            let url = try Self.write(
                env: env,
                day: day,
                objects: changed)
            #expect(Self.samples(
                env: env,
                day: day).isEmpty)
            changed = objects
            var payload = try #require(changed[changed.count - 2]["payload"] as? [String: Any])
            var total = try #require(payload["turn_token_usage"] as? [String: Any])
            total["output_tokens"] = 30
            payload["turn_token_usage"] = total
            changed[changed.count - 2]["payload"] = payload
            try env.jsonl(changed).write(
                to: url,
                atomically: true,
                encoding: .utf8)
            #expect(Self.samples(
                env: env,
                day: day).isEmpty)
        }
    }

    @Test
    func `malformed owned usage invalidates a turn instead of using an earlier partial total`() throws {
        try Self.withFixture { env, day, objects in
            var changed = objects
            var record = try #require(changed[changed.count - 2]["payload"] as? [String: Any])
            var usage = try #require(record["usage"] as? [String: Any])
            usage["reasoning_output_tokens"] = 100
            record["usage"] = usage
            changed[changed.count - 2]["payload"] = record
            _ = try Self.write(env: env, day: day, objects: changed)
            #expect(Self.samples(env: env, day: day).isEmpty)
        }
    }

    @Test
    func `malformed foreign records cannot invalidate an owned timing sample`() throws {
        try Self.withFixture { env, day, objects in
            var foreign = try #require(objects.first { $0["type"] as? String == "token_usage_record" })
            var payload = try #require(foreign["payload"] as? [String: Any])
            payload["thread_id"] = "foreign-parent"
            payload["usage"] = ["input_tokens": true, "output_tokens": -1]
            foreign["payload"] = payload
            _ = try Self.write(
                env: env,
                day: day,
                objects: objects + [foreign])
            #expect(Self.samples(
                env: env,
                day: day).first?.outputTokens == 20)
        }
    }

    @Test(arguments: ["\"invalid-timestamp\"", "null", "1234"])
    func `owned requests with invalid timestamps cannot leave a partial timing sample`(_ json: String) throws {
        try Self.withFixture { env, day, objects in
            var changed = objects
            changed[changed.count - 2]["timestamp"] = try JSONSerialization.jsonObject(
                with: Data(json.utf8),
                options: [.fragmentsAllowed])
            _ = try Self.write(
                env: env,
                day: day,
                objects: changed)
            #expect(Self.samples(
                env: env,
                day: day).isEmpty)
        }
    }

    @Test
    func `a terminal event with invalid timing invalidates a previously completed sample`() throws {
        try Self.withFixture { env, day, objects in
            let url = try Self.write(
                env: env,
                day: day,
                objects: objects)
            #expect(Self.samples(
                env: env,
                day: day).count == 1)
            var invalid = try #require(objects.last)
            invalid["timestamp"] = "invalid-timestamp"
            try Self.append(
                [invalid],
                to: url,
                env: env)
            #expect(Self.samples(
                env: env,
                day: day).isEmpty)
        }
    }

    @Test
    func `revision eight caches backfill timing under a byte budget without changing ledger rows`() throws {
        try Self.withFixture { env, day, objects in
            let url = try Self.write(
                env: env,
                day: day,
                objects: objects)
            let expected = Self.samples(
                env: env,
                day: day)
            #expect(expected.count == 1)
            var old = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
            var usage = try #require(old.files[url.path])
            let rows = usage.codexRows
            usage.codexParserRevision = 8
            usage.codexRequestLedgerState?.turnPerformance = nil
            old.files[url.path] = usage
            #expect(!CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: old).catchUpRequired)
            var observed: [CostUsageTurnPerformanceSample] = []
            for _ in 0..<40 {
                observed = Self.samples(
                    env: env,
                    day: day,
                    byteLimit: 128)
                if !observed.isEmpty { break }
            }
            #expect(observed == expected)
            let reopened = CostUsageStore(cacheRoot: env.cacheRoot).syncLoadCodexCache(calendar: .current)
            #expect(reopened.files[url.path]?.codexRows == rows)
            #expect(reopened.files[url.path]?.hasCurrentCodexParser == true)
        }
    }

    @Test
    func `bounded scans expose a sample only after its completion has been read`() throws {
        try Self.withFixture { env, day, objects in
            _ = try Self.write(
                env: env,
                day: day,
                objects: objects)
            #expect(Self.samples(
                env: env,
                day: day,
                byteLimit: 128).isEmpty)
            var samples: [CostUsageTurnPerformanceSample] = []
            for _ in 0..<40 {
                samples = Self.samples(
                    env: env,
                    day: day,
                    byteLimit: 128)
                if !samples.isEmpty { break }
            }
            #expect(samples.first?.outputTokens == 20)
        }
    }

    @Test
    func `summaries weight elapsed time and calculate a median without overflow`() throws {
        let date = Date(timeIntervalSince1970: 1000)
        let one = try #require(CostUsageTurnPerformanceSample(
            completedAt: date,
            outputTokens: 100,
            durationMilliseconds: 1000,
            firstTokenMilliseconds: 200))
        let two = try #require(CostUsageTurnPerformanceSample(
            completedAt: date,
            outputTokens: 100,
            durationMilliseconds: 9000,
            firstTokenMilliseconds: 800))
        let summary = try #require(CostUsageTurnPerformanceSummary(samples: [one, two]))
        #expect(summary.outputTokensPerSecond == 20)
        #expect(summary.medianFirstTokenMilliseconds == 500)
        #expect(summary.firstTokenSampleCount == 2)
        #expect(CostUsageTurnPerformanceSummary(samples: []) == nil)
        let huge = try #require(CostUsageTurnPerformanceSample(
            completedAt: date,
            outputTokens: Int.max,
            durationMilliseconds: Int.max))
        #expect(CostUsageTurnPerformanceSummary(samples: [huge, huge]) == nil)
    }

    private static func withFixture(
        _ body: (CostUsageTestEnvironment, Date, [[String: Any]]) throws -> Void) throws
    {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(
            year: 2026,
            month: 5,
            day: 10)
        try body(env, day, Self.objects(
            env: env,
            day: day))
    }

    private static func objects(
        env: CostUsageTestEnvironment,
        day: Date) throws -> [[String: Any]]
    {
        let prefix: [String: Any] = [
            "type": "session_meta", "timestamp": env.isoString(for: day), "payload": ["id": "synthetic-speed-0"],
        ]
        let turn = try CostUsageTurnPerformanceBenchmarkTests.turn(
            env: env,
            day: day,
            session: "synthetic-speed-0",
            turn: 0,
            requests: 2)
        return try [prefix] + (turn.split(separator: "\n").map {
            try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        })
    }

    private static func write(
        env: CostUsageTestEnvironment,
        day: Date,
        objects: [[String: Any]]) throws -> URL
    {
        let url = try env.writeCodexSessionFile(
            day: day,
            filename: "synthetic-speed.jsonl",
            contents: env.jsonl(objects))
        try FileManager.default.setAttributes([.modificationDate: day], ofItemAtPath: url.path)
        return url
    }

    private static func append(
        _ objects: [[String: Any]],
        to url: URL,
        env: CostUsageTestEnvironment) throws
    {
        let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(env.jsonl(objects).utf8))
        try FileManager.default.setAttributes(
            [.modificationDate: (modified ?? Date()).addingTimeInterval(2)], ofItemAtPath: url.path)
    }

    private static func samples(
        env: CostUsageTestEnvironment,
        day: Date,
        recorder: CostUsageScanner.CodexScanWorkRecorder? = nil,
        byteLimit: Int64 = 0,
        durationLimit: TimeInterval? = nil)
        -> [CostUsageTurnPerformanceSample]
    {
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite"),
            maxCodexSessionFileBytes: byteLimit,
            maxCodexScanBytesPerRefresh: 0,
            maxCodexScanDurationPerRefresh: durationLimit,
            codexScanWorkRecorderForTesting: recorder)
        options.refreshMinIntervalSeconds = 0
        let files = FileManager.default.enumerator(at: env.codexSessionsRoot, includingPropertiesForKeys: nil)
        let modified = files?.allObjects.compactMap { value -> Date? in
            guard let url = value as? URL, url.pathExtension == "jsonl" else { return nil }
            return (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        }.max() ?? day
        let report = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: modified.addingTimeInterval(1),
            options: options)
        #expect((report.summary?.totalTokens ?? 0) <= 220)
        let cache = CostUsageStore(cacheRoot: env.cacheRoot).syncLoadCodexCache(calendar: options.calendar)
        return CostUsageScanner.buildCodexSessionBreakdownsFromCache(
            cache: cache,
            range: .init(
                since: day,
                until: day),
            modelsDevCatalog: ModelsDevCatalog(providers: [:]))
            .flatMap(\.turnPerformanceSamples)
    }
}
