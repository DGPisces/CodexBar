import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct SpendSessionPerformanceTests {
    @Test
    func `dashboard filters timing samples by completion day and keeps providers separate`() throws {
        let now = try #require(CostUsageScanner.dateFromTimestamp("2026-05-10T12:00:00Z"))
        let today = try #require(CostUsageTurnPerformanceSample(
            completedAt: now,
            outputTokens: 100,
            durationMilliseconds: 1000,
            firstTokenMilliseconds: 100))
        let yesterday = try #require(CostUsageTurnPerformanceSample(
            completedAt: now.addingTimeInterval(-86400),
            outputTokens: 100,
            durationMilliseconds: 9000))
        for (provider, source) in [
            (UsageProvider.codex, SpendDashboardModel.SourceKind.native),
            (.claude, .native),
            (.codex, .openCodex),
        ] {
            let group = try Self.group(
                now: now,
                samples: [today, yesterday],
                provider: provider,
                source: source)
            let row = try #require(group.sessions.first)
            if provider == .codex, source == .native {
                #expect(row.turnPerformance?.sampleCount == 1)
                #expect(row.turnPerformance?.outputTokensPerSecond == 100)
            } else {
                #expect(row.turnPerformance == nil)
            }
        }
    }

    @Test
    func `labels describe whole turn throughput and omit missing first token timing`() throws {
        let sample = try #require(CostUsageTurnPerformanceSample(
            completedAt: Date(),
            outputTokens: 20,
            durationMilliseconds: 10000))
        let summary = try #require(CostUsageTurnPerformanceSummary(samples: [sample]))
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(spendSessionPerformanceText(summary) == "Turn output: 2.0 tok/s · Timed turns: 1")
        }
        CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            #expect(spendSessionPerformanceText(summary) == "整轮输出：2.0 tok/s · 计时轮数：1")
        }
    }

    @Test
    func `render production session rows with synthetic timing`() throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_PERFORMANCE_UI_PROOF_DIR"] else { return }
        let width = Double(ProcessInfo.processInfo.environment["CODEXBAR_PERFORMANCE_UI_PROOF_WIDTH"] ?? "") ?? 820
        let root = URL(
            fileURLWithPath: path,
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true)
        let now = try #require(CostUsageScanner.dateFromTimestamp("2026-05-10T12:00:00Z"))
        let sample = try #require(CostUsageTurnPerformanceSample(
            completedAt: now,
            outputTokens: 500,
            durationMilliseconds: 10000,
            firstTokenMilliseconds: 800))
        let group = try Self.group(
            now: now,
            samples: [sample, sample, sample])
        for language in ["en", "zh-Hans"] {
            for dark in [false, true] {
                try CodexBarLocalizationOverride.$appLanguage.withValue(language) {
                    let view = VStack(
                        alignment: .leading,
                        spacing: 12)
                    {
                        Text(L("Usage & Spend")).font(.title2.bold())
                        Text(L("Sessions")).font(.headline)
                        SpendSessionRows(
                            group: group,
                            hidePersonalInfo: false)
                        Divider()
                        SpendSessionRows(
                            group: group,
                            hidePersonalInfo: true)
                    }
                    .padding(20).frame(width: width)
                    .background(dark ? Color(
                        red: 0.12,
                        green: 0.12,
                        blue: 0.12) : .white)
                    .foregroundStyle(dark ? .white : .black)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    let bitmap = try NSBitmapImageRep(cgImage: #require(renderer.cgImage))
                    try #require(bitmap.representation(
                        using: .png,
                        properties: [:]))
                        .write(to: root.appendingPathComponent("sessions-\(language)-\(dark ? "dark" : "light").png"))
                }
            }
        }
    }

    private static func group(
        now: Date,
        samples: [CostUsageTurnPerformanceSample],
        provider: UsageProvider = .codex,
        source: SpendDashboardModel.SourceKind = .native) throws
        -> SpendDashboardModel.CurrencyGroup
    {
        let sessions = [CostUsageSessionBreakdown(
            sessionID: "synthetic-session",
            lastActivity: now,
            inputTokens: 2000,
            cachedInputTokens: 1000,
            outputTokens: 1500,
            totalTokens: 3500,
            requestCount: 3,
            costUSD: 0.03,
            modelBreakdowns: [],
            projectPath: "/synthetic/project",
            projectName: "Example project",
            title: "Check performance",
            turnPerformanceSamples: samples)]
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: 3500,
            sessionCostUSD: 0.03,
            last30DaysTokens: 3500,
            last30DaysCostUSD: 0.03,
            daily: [.init(
                date: "2026-05-10",
                inputTokens: 2000,
                outputTokens: 1500,
                totalTokens: 3500,
                costUSD: 0.03,
                modelsUsed: nil,
                modelBreakdowns: nil)],
            sessions: sessions,
            updatedAt: now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let model = SpendDashboardModel.build(
            inputs: [.init(
                provider: provider,
                displayName: "Codex",
                snapshot: snapshot,
                sourceKind: source)],
            requestedDays: 1,
            now: now,
            calendar: calendar)
        return try #require(model.groups.first)
    }
}
