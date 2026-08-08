# Programmatic Queue GUI Design

Status: living design record. Confirmed decisions are binding; unresolved items remain listed at the end until the design interview closes.

## Goals

- Replace the fixed GUIDE queue GUI with a GUI constructed entirely in MATLAB code.
- Give Available Scans and Queue substantially more space so more entries and longer names remain visible.
- Remove unused controls while preserving the compact Save, PowerPoint, Notifications, Schedule, and Console areas.
- Keep queue execution compatible with the existing `smaux.scans`, `smaux.smq`, scan editor, and measurement engine workflows.

## Architecture

- Keep `sm` as the public queue-GUI entry point so `smready` and existing scripts do not change.
- Replace the GUIDE construction path and binary `.fig` dependency with programmatic `figure`, `uipanel`, and `uicontrol` construction.
- Preserve the `smaux.sm` handle contract required by existing queue callbacks and shared GUI state helpers.
- Make the window resizable. Start near 1100 x 800 pixels with a practical minimum near 850 x 600 pixels. Do not persist geometry across MATLAB sessions initially.
- Queue scans continue to use turbo mode; direct runs from the scan GUI continue to use safe mode.
- Repeated Start clicks during an active scan remain silent no-ops before any queue or scan state changes.

## Shared Save and PowerPoint State

The scan and queue GUIs must be two views of the same state. They must not maintain independent filename, data-path, run-number, or PowerPoint state.

- Initialize the existing shared services with `smdatapathEnsureGlobals`, `smrunEnsureGlobals`, and `smpptEnsureGlobals` after `smbridgeAddSharedPaths`.
- Register the queue GUI as source `main` with `smdatapathRegisterGui`, `smrunRegisterGui`, and `smpptRegisterGui`.
- Read state only through the matching `*GetState` functions.
- Write state only through the matching `*UpdateGlobalState` functions, then refresh the source GUI with the matching `*ApplyStateToGui("main")` call. Updates must continue to broadcast to the scan GUI.
- Both GUIs pass an empty filename to `engine.run`. The engine remains responsible for collision-free `NNN_<scan-name>.mat` generation and shared run-number advancement.
- PowerPoint state is global and is read by the engine during final saving. There is no per-scan PowerPoint state.

## Layout

- Use one compact top strip, approximately 70 pixels high:
  - Save: 40 percent of the strip width.
  - PowerPoint: 35 percent.
  - Notifications: 25 percent.
- Keep Console at the bottom with a relatively stable height.
- Let Schedule absorb nearly all additional window height and width.
- Give Available Scans and Queue equal width.
- Place the shared queue-insertion buttons between the source area and Queue, above the vertical midpoint because Available Scans is the most frequently used source.
- Separate the insertion buttons enough to reduce accidental clicks.

## Top Blocks

### Save

- Keep `Path...`, a shortened path display with the full path available as a tooltip, and `Run #`.
- Remove AutoIncrement. Its legacy callback is inert, while the engine already advances the shared run number and skips filename collisions.

### PowerPoint

- Keep `Log to PowerPoint`, `File...`, and the selected filename.
- Remove QuickSave, Save Now, Figure, and all Priority controls.

### Notifications

- Display the engine-level Slack account as read-only text.
- Display exactly `Account not provided` when the account email is empty.
- Do not vary the display based on the selected scan.

Code audit result: normal configuration has no per-scan Slack authoring path. `recipe.slack_notification_account_email` is resolved by `smready` into `engine.slack_notification_settings.account_email`. The queue callback still contains a dormant compatibility branch that reads a manually supplied `scan.slack_notification_account_email`; no GUI, demo, or scan-building path creates that field.

## Schedule and Queue Interaction

- Retain Available Scans, Raw Commands, Queue, and their edit workflows.
- The active insertion source is the most recently selected Available Scans or Raw Commands panel.
- Highlight the active source panel and show a small changing label above the insertion controls.
- Available Scans and Raw Commands share three explicit insertion actions:
  - `Insert at Top`
  - `Insert After Selected`
  - `Add to End`
- Show the currently executing item separately as `Running: <name>` above Queue. Queue itself contains only pending items.
- Allow insert, delete, reorder, and edit operations on pending items during execution.
- Add compact `Move Up`, `Move Down`, and `Remove` controls below Queue; retain Delete-key removal.
- Double-clicking an available or queued scan opens it in the scan editor. Double-click never inserts or starts a scan.

## Execution Controls

- Replace Run and Pause with:
  - Green `Start`
  - Red `Stop Now`
  - Amber `Stop Queue`
- Remove Pause entirely.
- `Stop Now` requires confirmation equivalent to the scan-figure close confirmation. It gracefully stops the active scan, runs finish actions, saves partial data and stop metadata, and halts queue processing.
- `Stop Queue` requires no confirmation. It lets the current scan finish and then halts queue processing.
- Both stop actions leave every pending item in Queue.
- When idle, both stop buttons are disabled.
- After Stop Queue is requested, change its label to `Stopping After Current...` and disable it until execution ends.

## Removed Areas

- Comments
- QuickSave
- Pause
- Legacy Notifications user list
- Priority PowerPoint controls

## Unresolved Decisions

- Whether to remove the dormant runtime reader for `scan.slack_notification_account_email` or retain it as undocumented legacy compatibility.
- Exact vertical split between Available Scans and Raw Commands.
- Console default height and whether the user may collapse it.
- Detailed list labeling, keyboard shortcuts, empty-state text, and confirmation behavior for destructive queue edits.
- Close behavior for the queue GUI while a queue is active.
