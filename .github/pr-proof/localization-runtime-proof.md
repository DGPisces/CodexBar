The packaged debug app now exercises the shipped `NotificationsPane` and the production `UsageStore.handleCredentialOutcome → AppNotifications → UNUserNotificationCenter` path. The authentication failure is synthetic; notification delivery is real.

Notification-delivery source revision: `3515b3914`. The later startup-isolation verification uses `abc1bee04`.

- [Actual Chinese preferences window](notifications-pane-runtime-zh-Hans.png): the complete production pane in a running packaged app, with its selected language read through normal `UserDefaults` lookup and no TaskLocal localization override.
- [App receipt](runtime-app-zh-Hans.json): bundle identity, selected language, and settings copy observed inside that process.
- [macOS notification receipt](runtime-notification-zh-Hans.json): title/body returned by `UNUserNotificationCenter.deliveredNotifications()` after the production notification path submitted the request. This is not a mocked notification center or a string-only render.

The notification-check app copy has a separate identifier, `com.steipete.codexbar.localizationproof.debug`, and display name, `CodexBar Localization Proof`, to avoid changing notification permissions for an existing CodexBar installation. Only Info.plist identity fields and ad-hoc signatures differ from that packaged debug app. The app's system notification permission was temporarily enabled for the check and restored to off afterward. Receipt paths are reduced to the bundle basename; screenshots and receipts contain no account data or credentials, and no live provider fetch was executed.

After the isolation fix, the normally identified debug bundle (`com.steipete.codexbar.debug`) was rebuilt and launched directly with the documented flag. [Its current receipt](runtime-app-isolated-zh-Hans.json) records the isolated startup mode, normal language lookup and identical login-item status before/after settings initialization. The observed status was raw value `3` (`notFound`), so this observation is not presented as an enabled-login-item reproduction. Recording-service regression tests additionally verify that isolated initialization and later login-preference changes never call the updater at all, including the path that would unregister enabled or approval-pending services.

- [Current app window after isolation fix](notifications-pane-isolated-zh-Hans.png).
- [Read-only state comparison](startup-isolation-zh-Hans.json): four protected preference keys across the production/debug app and current/legacy debug shared domains stayed unchanged. Both debug widget snapshot paths were absent before and after the launch. Values, full paths and file contents are not included in this receipt.

To reproduce the app check:

```sh
CODEXBAR_SIGNING=adhoc ARCHES="$(uname -m)" ./Scripts/package_app.sh debug
./CodexBar.app/Contents/MacOS/CodexBar --localization-proof -appLanguage zh-Hans
```

The flag is DEBUG-only and enters before ordinary provider startup. It uses dictionary-backed defaults without Foundation search-domain fallback and configuration/credential paths inside the fixture directory. An explicit isolated settings startup skips login-item management, user-plugin discovery, app-group resolution/migration, legacy credential imports, provider detection and local usage-source discovery. Keychain access and UsageStore background fetching are disabled. The preferences view, localization lookup, credential-episode handling and notification submission remain the production implementations. Click **Send credential-expiry fixture**, allow notifications for the debug bundle, then click **Record delivered notification**. Receipts are written beneath the process temporary directory in `codexbar-localization-runtime-proof`.

The native widget extension includes a DEBUG-only `widget-bundle` diagnostic under subsystem `com.steipete.codexbar.localization`. When WidgetKit instantiates the installed extension, it records whether localization uses `Bundle.main`, the actual bundle identifier, and the preferred language selected by Foundation. This diagnostic does not set a language override or read account data.

The installed native Usage widget was added through macOS Edit Widgets to Notification Center. [Its receipt](native-widget-system-en.json) records the actual host accessibility identifier (`widget-local:…:CodexBarUsageWidget`), system preferences and visible English empty-state copy. [The widget-only screenshot](native-widget-system-en.png) is cropped to its title/body to exclude surrounding notifications, other widgets and desktop overlays. [The captured native extension log](native-widget-system-en.log) records `main=true bundle=com.steipete.codexbar.localizationproof.debug.widget language=en`; the running extension path was also checked against the temporary app copy built from `abc1bee04`. SwiftPM `main=false` test diagnostics and gallery fixture renders are excluded from this evidence. The system prefers `en-US`, independently of the app's `zh-Hans` selection; no system language or TaskLocal widget override was applied. The widget shows the actual empty state because no debug usage snapshot is available. The temporary widgets were removed afterward, leaving the four original Notification Center widgets in place.

[The completed full-suite summary](full-tests-isolated-startup.txt) covers the isolated-startup source revision: 1,526 discovered selections, 74/74 first-pass successful groups, zero failures/retries/timeouts, exit status 0, 1,143.8 seconds total.

Translation review used DeepL and contextual revision for the three affected strings in 21 non-English languages. The current DeepL desktop language picker did not offer Thai; Thai was translated directly. The final copy preserves the parser's literal `ctrl`, `alt`, `shift`, `cmd`, `left`, `right` and `none` tokens, keeps `Chutes` and `API`, and describes Amp credit balances as monetary/usage balances instead of weighing scales. Automated checks cover these contracts across all supported languages.
