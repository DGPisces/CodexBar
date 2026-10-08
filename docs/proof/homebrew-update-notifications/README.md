# Homebrew update notification: native application proof

This folder uses synthetic versions (`99.0.x`) and an isolated documentation-only bundle. No account, credential, usage history, private endpoint, or personal home path is included in the published receipts.

## Production route

The freshly built full CodexBar executable sends through the unchanged production `HomebrewUpdaterController` → `HomebrewUpdateNotifier.Dependencies.live` → `AppNotifications.shared` → `UNUserNotificationCenter`. The real notification center delegate is `AppNotifications.shared`; the fixture does not call or replace its notification response callbacks.

The production `AppDelegate.applicationWillFinishLaunching` registers the click handler. The production `configure`, pending settings-open state, `openSettings`, `SettingsWindowController`, `PreferencesView`, and `AboutPane` handle the resulting settings route. A fixture wrapper delays settings configuration by three seconds to exercise a notification response arriving before settings are ready. Ordinary provider and status-item startup is excluded from this fixture.

The build script temporarily adds a DEBUG entry guard and an updater-factory branch, and copies the documentation-only Swift launcher into the app target. It restores the original app source and removes the temporary helper in `finally`; normal builds contain neither the launcher nor the factory branch. The [build receipt](build-receipt.json) records the original and instrumented entry hashes, production source hashes, fixture hash, source commit, and executable hash.

The bundle is ad-hoc signed and passes `codesign --verify --deep --strict`. This validates native notification integration in a locally signed fixture app; it does not claim Developer ID notarization or delivery from the official distributed bundle.

## Evidence

The [native event receipt](native-events.jsonl) is an allowlisted diagnostic stream produced by the running application. Notification authorization and delivered/pending requests come from the real system notification center. Saved submitted versions and automatic-check preferences come from the isolated app's real persistent standard defaults. Settings visibility and selected pane come from the actual production window and preferences selection.

The [verification report](verification.json) checks compiled-source identity and observed lifecycle transitions. Click claims additionally require the native UI interaction transcript; opening settings through the fixture control is not notification-click proof.

The [validation receipt](validation-receipt.json) records passing code checks, 54 focused tests in six suites, and the complete inventory-verified regression run on the production commit in the build receipt: 14,081 methods, all 1,593 selections, and 144/144 groups passed on their first attempt, with no retries or timeouts. An earlier serial `make test` invocation was deliberately interrupted after eight successful groups to use the documented parallel runner; that interrupted run is not counted as a pass.

### Captured results

These receipts are partial native evidence from October 8, 2026. They do not clear the PR's remaining native click and saved-preference proof requirements.

| Behavior | Observed result |
| --- | --- |
| Native delivery | The system center returned the silent `99.0.1`, `99.0.2`, and `99.0.3` requests as delivered. The production notification delegate remained installed. |
| Permission state | Launch 1 observed denied authorization, no delivered request, and no saved submitted version in that snapshot. |
| Restart deduplication | Launch 2 loaded the saved `99.0.1` submission, performed one startup fetch, and did not submit that version again. |
| Visible banner | Pending; delivered-request diagnostics do not establish that a banner appeared on screen. |
| Running-app notification click | Pending; no notification click or About transition has been observed. |
| Cold-launch notification click | Pending. |
| Saved disabled checks after restart | Pending native UI verification; regression tests cover the controller behavior. |

The [interaction record](interaction-record.md) distinguishes system diagnostics from UI observations and documents the remaining steps. Launch 1 used an earlier fixture wrapper with the same production notifier sources; the current build receipt identifies the wrapper used for launch 2. It should not be used to attest the earlier wrapper's executable identity.

## Reproduce

```sh
python3 docs/proof/homebrew-update-notifications/build-app-proof.py .
open .build/homebrew-notification-proof/CodexBarUpdateProof.app
```

Allow notifications for **CodexBar Update Proof** if macOS has disabled them. The startup automatic check discovers the synthetic newer version. **Check next synthetic version** supplies a higher fixture cask version to the production automatic-check path. It never runs an actual Homebrew upgrade.

Use the real system notification to open About, quit the fixture with Command-Q while a new notification remains, then click that notification to cold-launch it. Restart without changing the fixture version to observe deduplication. Turn off automatic checks using the actual About toggle, quit, and relaunch; **Observe automatic check** then records whether the production controller fetched anything.

Copy the resulting `build-receipt.json` and `native-events.jsonl` from `.build/homebrew-notification-proof` into this directory, then run:

```sh
python3 docs/proof/homebrew-update-notifications/verify-native-proof.py .
```
