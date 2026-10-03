The packaged debug app now exercises the shipped `NotificationsPane` and the production `UsageStore.handleCredentialOutcome → AppNotifications → UNUserNotificationCenter` path. The authentication failure is synthetic; notification delivery is real.

Verified source revision: `3515b3914`.

- [Actual Chinese preferences window](notifications-pane-runtime-zh-Hans.png): the complete production pane in a running packaged app, with its selected language read through normal `UserDefaults` lookup and no TaskLocal localization override.
- [App receipt](runtime-app-zh-Hans.json): bundle identity, selected language, and settings copy observed inside that process.
- [macOS notification receipt](runtime-notification-zh-Hans.json): title/body returned by `UNUserNotificationCenter.deliveredNotifications()` after the production notification path submitted the request. This is not a mocked notification center or a string-only render.

The temporary app copy has a separate identifier, `com.steipete.codexbar.localizationproof.debug`, and display name, `CodexBar Localization Proof`, to avoid changing notification permissions for an existing CodexBar installation. Only Info.plist identity fields and ad-hoc signatures differ from the packaged debug app. The app's system notification permission was temporarily enabled for the check and restored to off afterward. Receipt paths are reduced to the bundle basename; no account data or credentials are used.

To reproduce the app check:

```sh
CODEXBAR_SIGNING=adhoc ARCHES="$(uname -m)" ./Scripts/package_app.sh debug
./CodexBar.app/Contents/MacOS/CodexBar --localization-proof -appLanguage zh-Hans
```

The flag is DEBUG-only and enters before ordinary provider startup. It uses an isolated config/defaults suite, disables Keychain access, and prevents background fetching. The preferences view, localization lookup, credential-episode handling and notification submission remain the production implementations. Click **Send credential-expiry fixture**, allow notifications for the debug bundle, then click **Record delivered notification**. Receipts are written beneath the process temporary directory in `codexbar-localization-runtime-proof`.

The native widget extension includes a DEBUG-only `widget-bundle` diagnostic under subsystem `com.steipete.codexbar.localization`. When WidgetKit instantiates the installed extension, it records whether localization uses `Bundle.main`, the actual bundle identifier, and the preferred language selected by Foundation. This diagnostic does not set a language override or read account data.

Installed-widget runtime proof remains pending. The temporary extension was registered successfully as `com.steipete.codexbar.localizationproof.debug.widget`, but the desktop automation interface rejects clicks on Finder's desktop with `noWindowsAvailable` and on the widget host with `windowNotFoundAtPosition`. No widget-host localization log has been observed, so registration, the native build and earlier synthetic widget renders are not presented as installed-widget runtime evidence. The host system currently prefers English (`en-US`), independently of the app's `zh-Hans` selection. After adding the temporary Usage widget through macOS Edit Widgets, collect the `widget-bundle` diagnostic and a screenshot of that widget only.

Translation review used DeepL and contextual revision for the three affected strings in 21 non-English languages. The current DeepL desktop language picker did not offer Thai; Thai was translated directly. The final copy preserves the parser's literal `ctrl`, `alt`, `shift`, `cmd`, `left`, `right` and `none` tokens, keeps `Chutes` and `API`, and describes Amp credit balances as monetary/usage balances instead of weighing scales. Automated checks cover these contracts across all supported languages.
