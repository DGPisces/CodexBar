import CodexBarCore
import SwiftUI

struct SpendSessionPerformanceView: View {
    let summary: CostUsageTurnPerformanceSummary

    var body: some View {
        Text(spendSessionPerformanceText(self.summary))
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .fixedSize(
                horizontal: false,
                vertical: true)
            .help(self.tooltip)
    }

    private var tooltip: String {
        L("spend_turn_performance_help") + "\n" + L(
            "First-token samples: %@ / %@",
            codexBarLocalizedInteger(self.summary.firstTokenSampleCount),
            codexBarLocalizedInteger(self.summary.sampleCount))
    }
}

func spendSessionPerformanceText(_ summary: CostUsageTurnPerformanceSummary) -> String {
    func number(_ value: Double) -> String {
        value.formatted(.number.locale(codexBarLocalizedLocale()).precision(.fractionLength(1)))
    }
    var parts = [L("Turn output: %@ tok/s", number(summary.outputTokensPerSecond))]
    if let firstToken = summary.medianFirstTokenMilliseconds {
        parts.append(L("First token: %@ s", number(firstToken / 1000)))
    }
    parts.append(L("Timed turns: %@", codexBarLocalizedInteger(summary.sampleCount)))
    return parts.joined(separator: " · ")
}
