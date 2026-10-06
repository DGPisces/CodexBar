import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct LocalizationSemanticContractTests {
    @Test(arguments: [
        ("in 2d", "di 2 hari"),
        ("in 2d 18h", "di 2 hari 18j"),
        ("in 2d 5m", "di 2 hari 5m"),
        ("in 18h", "di 18j"),
        ("in 18h 5m", "di 18j 5m"),
        ("in 5m", "di 5m"),
    ])
    func `Indonesian provider countdowns preserve distinct day hour and minute units`(
        countdown: String,
        expected: String) throws
    {
        try CodexBarLocalizationOverride.$appLanguage.withValue("id") {
            let details = try ProviderDetailSection(title: "Quota details", rows: [
                .init(label: "Period", value: "peak \(countdown)", secondaryValue: "off-peak \(countdown)"),
            ])
            let localized = UsageMenuCardView.Model.localizedProviderDetails([details], provider: .zai)
            let row = try #require(localized.first?.rows.first)
            #expect(row.value == "\(L("peak")) \(expected)")
            #expect(row.secondaryValue == "\(L("off-peak")) \(expected)")
        }
    }

    @Test(arguments: AppLanguage.allCases.filter { $0 != .system })
    func `login and recovery translations preserve executable commands`(language: AppLanguage) {
        #expect(L("vertex_ai_login_instructions", language: language.rawValue)
            .contains("gcloud auth application-default login"))
        let recovery = L("managed_login_failed", language: language.rawValue)
        #expect(recovery.contains("codex --version"))
        #expect(recovery.contains("npm install -g --include=optional @openai/codex@latest"))
    }

    private static let shortcutHelp = "These shortcuts work while the provider switcher menu is open. "
        + "Use ctrl, alt, shift and cmd with a letter, digit, left or right; use none to disable an action."

    @Test(arguments: AppLanguage.allCases.filter { $0 != .system })
    func `translated shortcut instructions preserve the parser grammar`(language: AppLanguage) throws {
        let help = L(Self.shortcutHelp, language: language.rawValue)
        for token in ["ctrl", "alt", "shift", "cmd", "left", "right", "none"] {
            #expect(
                help.range(of: "\\b\(token)\\b", options: .regularExpression) != nil,
                "Missing literal shortcut token \(token) in \(language.rawValue)")
        }
        // Exercise exactly the input described in the help, including both directional keys.
        #expect(try ProviderSwitcherShortcuts.normalized("ctrl+alt+shift+cmd+left") ==
            "ctrl+alt+shift+cmd+left")
        #expect(try ProviderSwitcherShortcuts.normalized("shift+right") == "shift+right")
        #expect(try ProviderSwitcherShortcuts.normalized("none") == "none")
    }

    @Test(arguments: AppLanguage.allCases.filter { $0 != .system })
    func `Chutes credential placeholders retain the service and API names`(language: AppLanguage) {
        let placeholder = L("chutes key...", language: language.rawValue)
        #expect(placeholder.contains("Chutes"))
        #expect(placeholder.contains("API"))
    }

    @Test
    func `German Amp credit hint describes financial balances`() {
        let hint = L("Individual and workspace credit balances from Amp.", language: "de")
        #expect(hint.contains("Guthaben"))
        #expect(hint.contains("Arbeitsbereich"))
        #expect(hint.contains("Amp"))
        #expect(!hint.contains("Waagen"))
        #expect(!hint.contains("waagen"))
    }
}
