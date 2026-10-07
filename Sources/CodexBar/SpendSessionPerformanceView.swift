import CodexBarCore
import SwiftUI

struct SpendSessionPerformanceView: View {
    let summary: CostUsageTurnPerformanceSummary
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(spendSessionPerformanceText(self.summary))
                .help(self.tooltip)
            DisclosureGroup(L("Performance details"), isExpanded: self.$expanded) {
                SpendSessionPerformanceDetailsView(summary: self.summary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
    }

    private var tooltip: String {
        L("spend_turn_performance_help") + "\n" + L(
            "Timed turns: %@", codexBarLocalizedInteger(self.summary.sampleCount)) + "\n" + L(
            "First-token samples: %@ / %@",
            codexBarLocalizedInteger(self.summary.firstTokenSampleCount),
            codexBarLocalizedInteger(self.summary.sampleCount))
    }
}

func spendSessionPerformanceText(_ summary: CostUsageTurnPerformanceSummary) -> String {
    func number(_ value: Double) -> String {
        value.formatted(.number.locale(codexBarLocalizedLocale()).precision(.fractionLength(1)))
    }
    var parts: [String] = []
    if let firstToken = summary.medianFirstTokenMilliseconds {
        parts.append(L("First token: %@ s", number(firstToken / 1000)))
    }
    parts.append(L("Turn output: %@ tok/s", number(summary.outputTokensPerSecond)))
    parts.append(L("Turn duration: %@ s", number(summary.medianDurationMilliseconds / 1000)))
    return parts.joined(separator: " · ")
}

struct SpendSessionPerformanceDetailsView: View {
    let summary: CostUsageTurnPerformanceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(spendSessionPerformanceDetailLines(self.summary), id: \.self) { Text($0) }
            Text(L("Observed turns; workload and tools affect these results."))
                .font(.caption2)
            Divider()
            Text(L("By model and reasoning effort")).fontWeight(.medium)
            ForEach(Array(self.summary.details.groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: 2) {
                    Text((group.model ?? L("Unknown model")) + " · " +
                        (group.reasoningEffort ?? L("Unknown reasoning effort")))
                    Text(spendSessionPerformanceGroupText(group))
                }
            }
            Text(L("Model first token may be reasoning, before visible answer text."))
                .font(.caption2)
        }
        .padding(.top, 4)
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
    }
}

func spendSessionPerformanceDetailLines(_ summary: CostUsageTurnPerformanceSummary) -> [String] {
    let details = summary.details
    func number(_ value: Double) -> String {
        value.formatted(.number.locale(codexBarLocalizedLocale()).precision(.fractionLength(1)))
    }
    var lines = [L("Timed turns: %@", codexBarLocalizedInteger(summary.sampleCount))]
    if let first = details.p95FirstTokenMilliseconds {
        lines.append(L("P95 first token: %@ s", number(first / 1000)))
    } else {
        lines.append(L("P95 first token: %@ / 20 samples", codexBarLocalizedInteger(summary.firstTokenSampleCount)))
    }
    if let duration = details.p95DurationMilliseconds {
        lines.append(L("P95 turn duration: %@ s", number(duration / 1000)))
    } else {
        lines.append(L("P95 turn duration: %@ / 20 samples", codexBarLocalizedInteger(summary.sampleCount)))
    }
    if let lower = details.outputRateLowerQuartile, let upper = details.outputRateUpperQuartile {
        lines.append(L("Middle 50%% of turns: %@–%@ tok/s", number(lower), number(upper)))
    } else {
        lines.append(L("Speed range needs 4 completed turns."))
    }
    if let cached = details.cachedInputFraction {
        lines.append(L(
            "Cached input: %@%% (%@ / %@ turns)",
            number(cached * 100),
            codexBarLocalizedInteger(details.cacheSampleCount),
            codexBarLocalizedInteger(summary.sampleCount)))
    } else {
        lines.append(L("Cached input: unavailable"))
    }
    return lines
}

func spendSessionPerformanceGroupText(_ group: CostUsageTurnPerformanceDetails.Group) -> String {
    func number(_ value: Double) -> String {
        value.formatted(.number.locale(codexBarLocalizedLocale()).precision(.fractionLength(1)))
    }
    var parts = [L("Timed turns: %@", codexBarLocalizedInteger(group.sampleCount))]
    if let first = group.medianFirstTokenMilliseconds {
        parts.append(L("First token: %@ s", number(first / 1000)) +
            " (" + codexBarLocalizedInteger(group.firstTokenSampleCount) + "/" +
            codexBarLocalizedInteger(group.sampleCount) + ")")
    }
    parts.append(L("Turn output: %@ tok/s", number(group.outputTokensPerSecond)))
    parts.append(L("Turn duration: %@ s", number(group.medianDurationMilliseconds / 1000)))
    return parts.joined(separator: " · ")
}
