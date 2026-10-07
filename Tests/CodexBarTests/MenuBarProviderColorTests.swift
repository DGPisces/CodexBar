import AppKit
import CodexBarCore
import Foundation
import Observation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct MenuBarProviderColorTests {
    private let now = Date(timeIntervalSince1970: 1_752_768_000)

    private final class ObservationFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func set() {
            self.lock.lock()
            self.value = true
            self.lock.unlock()
        }

        func get() -> Bool {
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.value
        }
    }

    // MARK: - Settings & Persistence

    @Test
    func `provider color defaults off persists and triggers menu observation`() {
        let defaults = InMemoryUserDefaults()
        let store = testSettingsStore(suiteName: "provider-color", userDefaults: defaults)
        #expect(!store.menuBarColorByProvider)

        let changed = ObservationFlag()
        withObservationTracking {
            _ = store.menuObservationToken
        } onChange: {
            changed.set()
        }

        store.menuBarColorByProvider = true
        #expect(changed.get())
        #expect(defaults.bool(forKey: "menuBarColorByProvider"))

        let restored = testSettingsStore(suiteName: "provider-color-restored", userDefaults: defaults)
        #expect(restored.menuBarColorByProvider)
    }

    @Test
    func `portable preferences round trip includes color by provider`() throws {
        let sourceDefaults = InMemoryUserDefaults()
        let source = testSettingsStore(suiteName: "provider-color-source", userDefaults: sourceDefaults)
        source.menuBarColorByProvider = true

        let targetDefaults = InMemoryUserDefaults()
        let target = testSettingsStore(suiteName: "provider-color-target", userDefaults: targetDefaults)
        #expect(!target.menuBarColorByProvider)

        let document = try PreferencesDocument(data: source.exportPreferences().encoded())
        try target.importPreferences(document)
        #expect(target.menuBarColorByProvider)
    }

    // MARK: - Contrast Policy & Relative Luminance

    @Test
    func `contrast policy accepts standard provider accents in dark and light appearance`() {
        for provider in [UsageProvider.claude, .codex, .copilot, .cursor] {
            let darkOptions = self.options(appearanceName: "darkAqua", colorByProvider: true)
            let darkTint = MenuBarLayoutRenderer.effectiveProviderTintColor(for: provider, options: darkOptions)
            #expect(darkTint != nil, "Expected accent for \(provider) to meet contrast in dark appearance")

            let lightOptions = self.options(appearanceName: "aqua", colorByProvider: true)
            let lightTint = MenuBarLayoutRenderer.effectiveProviderTintColor(for: provider, options: lightOptions)
            #expect(lightTint != nil, "Expected accent for \(provider) to meet contrast in light appearance")
        }
    }

    @Test
    func `contrast policy rejects low contrast colors`() {
        // Pure white (#FFFFFF) has 1.0:1 contrast against light background (fails >= 2.0:1)
        let whiteMeetsLight = MenuBarLayoutRenderer.meetsAppearanceContrast(
            accent: ProviderColor(hex: 0xFFFFFF),
            appearanceName: "aqua")
        #expect(!whiteMeetsLight)

        // Pure black (#000000) has 1.0:1 contrast against dark background (fails >= 2.0:1)
        let blackMeetsDark = MenuBarLayoutRenderer.meetsAppearanceContrast(
            accent: ProviderColor(hex: 0x000000),
            appearanceName: "darkAqua")
        #expect(!blackMeetsDark)
    }

    @Test
    func `contrast policy falls back when highlighted stale or under high contrast`() {
        let provider = UsageProvider.claude

        // Highlighted (menu open) must fall back to monochrome
        let highlightedOptions = self.options(isHighlighted: true, colorByProvider: true)
        let highlightedTint = MenuBarLayoutRenderer.effectiveProviderTintColor(
            for: provider,
            options: highlightedOptions)
        #expect(highlightedTint == nil)

        // Stale data must fall back to monochrome
        let staleOptions = self.options(isStale: true, colorByProvider: true)
        let staleTint = MenuBarLayoutRenderer.effectiveProviderTintColor(
            for: provider,
            options: staleOptions)
        #expect(staleTint == nil)

        // High contrast mode must fall back to monochrome
        let highContrastOptions = self.options(colorByProvider: true, highContrast: true)
        let highContrastTint = MenuBarLayoutRenderer.effectiveProviderTintColor(
            for: provider,
            options: highContrastOptions)
        #expect(highContrastTint == nil)
    }

    // MARK: - Layout Rendering & Attributed Output

    @Test(arguments: ["aqua", "darkAqua"])
    func `color by provider tints brand icon and percent tokens`(appearance: String) throws {
        let renderer = MenuBarLayoutRenderer()
        let icon = NSImage(size: NSSize(width: 16, height: 16))
        icon.isTemplate = true

        let layout = MenuBarLayout(lines: [[.icon, .percent(window: .session), .percent(window: .weekly)]])
        let data = self.data(provider: .claude)

        // Baseline (colorByProvider: false) -> monochrome template rendering
        let plainOptions = self.options(appearanceName: appearance, colorByProvider: false)
        let plain = renderer.render(layout: layout, data: data, icon: icon, options: plainOptions)
        #expect(plain.leadingIcon != nil)
        #expect(plain.leadingIcon?.isTemplate == true)

        // Opt-in (colorByProvider: true) -> tinted attributed title with attachment icon
        let coloredOptions = self.options(appearanceName: appearance, colorByProvider: true)
        let colored = renderer.render(layout: layout, data: data, icon: icon, options: coloredOptions)
        #expect(colored.leadingIcon == nil)
        #expect(colored.statusImage == nil)

        let expectedAccent = ProviderAccentPalette.color(for: .claude)

        // Verify percent tokens have the accent color applied
        let title = colored.attributedTitle
        let string = title.string
        let sessionRange = (string as NSString).range(of: "25%")
        let weeklyRange = (string as NSString).range(of: "60%")
        try #require(sessionRange.location != NSNotFound)
        try #require(weeklyRange.location != NSNotFound)

        let sessionColor = title.attribute(.foregroundColor, at: sessionRange.location, effectiveRange: nil) as? NSColor
        let weeklyColor = title.attribute(.foregroundColor, at: weeklyRange.location, effectiveRange: nil) as? NSColor
        let expectedColor = NSColor(
            srgbRed: expectedAccent.red,
            green: expectedAccent.green,
            blue: expectedAccent.blue,
            alpha: 1.0)
        #expect(sessionColor == expectedColor)
        #expect(weeklyColor == expectedColor)

        // Button application applies attributed title directly without button image
        let button = NSButton()
        _ = StatusItemController.applyMenuBarLayoutContent(colored, for: button, gap: .regular)
        #expect(button.image == nil)
        #expect(button.attributedTitle.string == colored.attributedTitle.string)
    }

    @Test
    func `color by provider preserves pace colors when both are enabled`() throws {
        let renderer = MenuBarLayoutRenderer()
        let layout = MenuBarLayout(lines: [[.percent(window: .session), .pace(window: .weekly)]])
        let data = self.data(provider: .codex)

        let options = self.options(colorPace: true, colorByProvider: true)
        let output = renderer.render(layout: layout, data: data, icon: nil, options: options)

        let title = output.attributedTitle
        let string = title.string
        let percentRange = (string as NSString).range(of: "25%")
        let paceRange = (string as NSString).range(of: "+11%")
        try #require(percentRange.location != NSNotFound)
        try #require(paceRange.location != NSNotFound)

        let percentColor = title.attribute(.foregroundColor, at: percentRange.location, effectiveRange: nil) as? NSColor
        let paceColor = title.attribute(.foregroundColor, at: paceRange.location, effectiveRange: nil) as? NSColor

        let codexAccent = ProviderAccentPalette.color(for: .codex)
        let expectedCodexColor = NSColor(
            srgbRed: codexAccent.red,
            green: codexAccent.green,
            blue: codexAccent.blue,
            alpha: 1.0)
        #expect(percentColor == expectedCodexColor)
        #expect(paceColor == .systemRed)
    }

    @Test
    func `color by provider falls back to monochrome when highlighted or stale`() {
        let renderer = MenuBarLayoutRenderer()
        let layout = MenuBarLayout(lines: [[.percent(window: .session)]])
        let data = self.data(provider: .claude)

        // Highlighted status item
        let highlightedOptions = self.options(isHighlighted: true, colorByProvider: true)
        let highlighted = renderer.render(layout: layout, data: data, icon: nil, options: highlightedOptions)
        let highlightedColor = highlighted.attributedTitle.attribute(
            .foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(highlightedColor == .controlTextColor)

        // Stale data
        let staleOptions = self.options(isStale: true, colorByProvider: true)
        let stale = renderer.render(layout: layout, data: data, icon: nil, options: staleOptions)
        let staleColor = stale.attributedTitle.attribute(
            .foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(staleColor == .secondaryLabelColor)
    }

    // MARK: - Offscreen Proof PNG Generation

    @Test
    func `render provider color proof PNGs`() throws {
        let env = ProcessInfo.processInfo.environment
        guard let outputDir = env["CODEXBAR_PROVIDER_COLOR_PROOF_DIR"] else {
            return
        }
        let dirURL = URL(fileURLWithPath: outputDir, isDirectory: true)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let renderer = MenuBarLayoutRenderer()
        let layout = MenuBarLayout(lines: [[.icon, .percent(window: .session), .percent(window: .weekly)]])
        let data = self.data(provider: .claude)
        let icon = ProviderBrandIcon.image(for: .claude)

        struct ProofCase {
            let name: String
            let colorByProvider: Bool
            let isDark: Bool
            let isHighlighted: Bool
            let isStale: Bool
        }

        let cases: [ProofCase] = [
            ProofCase(
                name: "before-setting-off",
                colorByProvider: false,
                isDark: true,
                isHighlighted: false,
                isStale: false),
            ProofCase(
                name: "after-setting-on-dark",
                colorByProvider: true,
                isDark: true,
                isHighlighted: false,
                isStale: false),
            ProofCase(
                name: "after-setting-on-light",
                colorByProvider: true,
                isDark: false,
                isHighlighted: false,
                isStale: false),
            ProofCase(
                name: "after-setting-on-highlighted",
                colorByProvider: true,
                isDark: true,
                isHighlighted: true,
                isStale: false),
            ProofCase(
                name: "after-setting-on-stale",
                colorByProvider: true,
                isDark: true,
                isHighlighted: false,
                isStale: true),
        ]

        for c in cases {
            let appearanceName = c.isDark ? "darkAqua" : "aqua"
            let options = self.options(
                appearanceName: appearanceName,
                isStale: c.isStale,
                isHighlighted: c.isHighlighted,
                colorByProvider: c.colorByProvider)
            let rendered = renderer.render(layout: layout, data: data, icon: icon, options: options)

            let button = NSButton()
            button.isBordered = false
            let width = StatusItemController.applyMenuBarLayoutContent(rendered, for: button, gap: .regular)
            let renderWidth = max(width + 16, 80)
            let height: CGFloat = 24
            button.frame = NSRect(x: 8, y: 0, width: width, height: height)

            let container = NSView(frame: NSRect(x: 0, y: 0, width: renderWidth, height: height))
            let appearance = try #require(NSAppearance(named: c.isDark ? .darkAqua : .aqua))
            container.appearance = appearance
            button.appearance = appearance
            container.addSubview(button)

            let scale: CGFloat = 2.0
            let rep = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(renderWidth * scale),
                pixelsHigh: Int(height * scale),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0))
            rep.size = NSSize(width: renderWidth, height: height)

            appearance.performAsCurrentDrawingAppearance {
                guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = ctx

                let bgColor: NSColor = if c.isHighlighted {
                    .selectedContentBackgroundColor
                } else if c.isDark {
                    NSColor(srgbRed: 0.14, green: 0.15, blue: 0.17, alpha: 1.0)
                } else {
                    NSColor(srgbRed: 0.92, green: 0.93, blue: 0.94, alpha: 1.0)
                }
                bgColor.setFill()
                NSRect(x: 0, y: 0, width: renderWidth, height: height).fill()

                container.displayIgnoringOpacity(container.bounds, in: ctx)
                NSGraphicsContext.restoreGraphicsState()
            }

            let pngData = try #require(rep.representation(using: .png, properties: [:]))
            let fileURL = dirURL.appendingPathComponent("\(c.name).png")
            try pngData.write(to: fileURL)
            #expect(!pngData.isEmpty)
        }
    }

    // MARK: - Fixtures & Helpers

    private func data(provider: UsageProvider = .codex) -> MenuBarLayoutRenderData {
        MenuBarLayoutRendererTests().data(provider: provider)
    }

    private func options(
        appearanceName: String = "darkAqua",
        isStale: Bool = false,
        isHighlighted: Bool = false,
        colorPace: Bool = false,
        colorByProvider: Bool = false,
        highContrast: Bool = false) -> MenuBarLayoutRenderOptions
    {
        MenuBarLayoutRenderOptions(
            size: .regular,
            highContrast: highContrast,
            showUsed: true,
            conditionals: [],
            appearanceName: appearanceName,
            isDebugApp: false,
            isStale: isStale,
            isHighlighted: isHighlighted,
            now: self.now,
            verticalAdjustment: 0,
            colorPace: colorPace,
            colorByProvider: colorByProvider,
            forceStackedStyle: false)
    }
}
