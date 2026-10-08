# Native notification interaction record

All versions and accounts in this fixture are synthetic. The fixture has its own application identifier and preference domain. No live provider requests or Homebrew installation were performed.

## Observed actions

1. Built the full application from production commit `c16e1a6f7f6f85be9e6f9b26bdd2438e3d57e8f9`, with the documentation-only entry point and synthetic updater dependencies described in the build receipt. The bundle passed strict ad-hoc signature verification.
2. Launch 1 observed the system's denied notification authorization. The production notifier did not save a successfully submitted version.
3. Enabled notifications for the fixture application through the macOS Notifications settings page. The real system center subsequently returned the `99.0.1` notification as delivered, and the production notifier saved that version.
4. Rebuilt the fixture to add its control window and exclude ordinary provider/status-item startup. Production notification and settings-route sources were unchanged. Launch 2 loaded the saved submitted version, ran its automatic startup check, and did not submit `99.0.1` again.
5. Clicked **Check next synthetic version** twice in the fixture control window. Those controls called the production automatic-check path. The real system center returned the successive silent `99.0.2` and `99.0.3` requests as delivered.

The **Open update settings** control was not used. No real notification card was clicked during these recorded actions, and no click-to-About or cold-launch behavior is claimed.

## Remaining native interactions

The computer-use surface exposed notification widgets but not the notification cards; a later attempt was blocked by the locked Mac. This prevents autonomous native notification clicking with the available interface. The pending human-assisted action is to unlock the Mac and click the fixture's `99.0.3` notification.

After that click:

1. Confirm the real settings window opens on About, correlate its transition with the native event receipt, and capture redacted UI evidence.
2. Close settings, produce a newer synthetic notification, quit the fixture with Command-Q, then click that system notification to launch it. Confirm About opens after delayed production settings configuration.
3. Restart again without changing the available version and confirm no additional notification is submitted.
4. Turn off automatic checks using the actual About toggle, quit, and launch the fixture again. Confirm the saved preference is false, no automatic fetch occurs, and old update notifications are retired. Use **Observe automatic check** to verify the automatic path still performs zero fetches.

Refresh the public event and verification receipts after those interactions. Until then, the evidence remains incomplete and the PR remains a draft.
