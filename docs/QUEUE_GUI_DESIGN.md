# Programmatic Queue GUI Design

Status: binding design and regression contract for the ongoing programmatic
replacement. The current `dev` implementation remains GUIDE-based until the
replacement lands. Confirmed decisions are binding; unresolved items remain
listed at the end and must not be decided silently during implementation.

## Goals

- Replace the fixed GUIDE queue GUI with a GUI constructed entirely in MATLAB code.
- Give Available Scans and Queue substantially more space so more entries and longer names remain visible.
- Remove unused controls while preserving the compact Save, PowerPoint, Notifications, and Schedule areas.
- Keep queue execution compatible with the existing `smaux.scans`, `smaux.smq`, scan editor, and measurement engine workflows.
- Permit visual and layout changes without regressing queue, scan-library, shared-state, stop, error, or close/reopen behavior.

## Change-Control Rule

This file is the single source of truth for the queue-GUI replacement. A visual
change may alter geometry, styling, labels, and the controls explicitly listed
as removed or replaced here. It must not alter any other behavior in the
functional contract or acceptance matrix.

If implementation needs behavior not specified here, add it to **Unresolved
Decisions** and resolve it before coding. Do not infer behavior from convenient
widget callbacks or from the lifetime of the figure.

## Architecture

- Keep `sm` as the public queue-GUI entry point so `smready` and existing scripts do not change.
- Replace the GUIDE construction path and binary `.fig` dependency with programmatic `figure`, `uipanel`, and `uicontrol` construction.
- Keep canonical scan-library, pending-queue, running-item, and queue-control state outside the queue figure in a GUI-independent state owner.
- Treat the queue GUI as a disposable view of that state. Closing the figure must not stop execution, clear state, or otherwise affect the scan/queue system.
- A plain `sm` call creates and attaches a queue GUI when none exists, or raises the existing queue GUI when one is already open. At most one queue GUI may exist.
- `sm` requires an initialized measurement engine. Before `smready(...)`, it throws `sm:MissingEngine` with a direct setup instruction instead of opening a partial GUI.
- Preserve the `smaux.sm` handle contract only as the currently attached view contract required by existing callbacks and shared GUI state helpers.
- Make the window resizable. Start near 1100 x 800 pixels with a practical minimum near 850 x 600 pixels. Do not persist geometry across MATLAB sessions initially.
- Queue scans continue to use turbo mode; direct runs from the scan GUI continue to use safe mode.
- Repeated Start clicks during an active scan remain silent no-ops before any queue or scan state changes.
- Keep the existing synchronous `engine.run` contract. Closing the queue GUI does not interrupt execution, but a Command Window `sm` call cannot execute until MATLAB returns from the active scan callback; do not expand this project into an asynchronous engine rewrite.
- If `smready(...)` is called while an engine scan is active or the queue phase is
  non-idle, throw `smready:ScanActive` before replacing state. This includes a
  raw command and the between-item pause, even when
  `engine.isScanInProgress == false`. When idle, rebind to the new engine while
  preserving the scan library, pending queue, raw-command draft, and shared
  Save, PowerPoint, and run state.

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
- Let Schedule use all space below the compact top strip and absorb all additional window height and width.
- Give Available Scans and Queue equal width.
- Divide the left source area vertically: Available Scans receives 80 percent and Raw Commands receives 20 percent.
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

Code audit result: normal configuration has no per-scan Slack authoring path. `recipe.slack_notification_account_email` is resolved by `smready` into `engine.slack_notification_settings.account_email`. Remove the dormant compatibility branch that reads a manually supplied `scan.slack_notification_account_email`; no GUI, demo, or scan-building path creates that field.

## Schedule and Queue Interaction

- Retain Available Scans, Raw Commands, Queue, and their edit workflows.
- The active insertion source defaults to Available Scans on first launch and
  thereafter is the most recently selected Available Scans or Raw Commands panel.
- Highlight the active source panel and show a small changing label above the insertion controls.
- Preserve the raw-command draft, active source, and selected scan/queue item identities when the view is closed. Revalidate stored selections when the model changes; do not preserve list scroll positions or window geometry.
- Available Scans and Raw Commands share three explicit insertion actions:
  - `Insert at Top`
  - `Insert After Selected`
  - `Add to End`
- Show the currently executing item separately as `Running: <name>` above Queue. Queue itself contains only pending items.
- Allow insert, delete, reorder, and edit operations on pending items during execution.
- Add compact `Move Up`, `Move Down`, and `Remove` controls below Queue; retain Delete-key removal.
- Keep both lists single-select. Removing one pending item takes effect immediately without confirmation; do not add a bulk Clear Queue control.
- Retain Delete-key removal of the selected Available Scan. The current behavior
  is immediate and remains the compatibility baseline unless the confirmation
  decision below is deliberately changed.
- Double-clicking an available or queued scan opens it in the scan editor. Double-click never inserts or starts a scan.
- `TO SCANS` and `TO QUEUE` in the scan GUI update the independent state and then summon `sm` if the queue GUI is absent. If it already exists, refresh the same singleton view without stealing keyboard focus.

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
- Closing the queue GUI is always allowed and has no queue or scan side effects. If execution continues without a view, a later `sm` call recreates the singleton view and reflects the current state.

## Functional Compatibility Contract

Unless a behavior appears in **Intentional Current-to-Target Changes**, the
replacement must preserve it. The model transition is authoritative; rendering
the result is secondary and may be skipped when no valid queue view exists.

### Entry Point and View Lifetime

- `sm` remains the only public queue-GUI entry point. Before `smready(...)`, it
  throws `sm:MissingEngine` and creates no partial model or view.
- Repeated `sm` calls return and raise the one attached valid figure. They never
  create duplicate queue windows.
- Closing the queue figure detaches and deletes only the view. It does not stop
  a scan, stop queue processing, clear the library or pending queue, reset the
  raw-command draft, or alter shared Save/PowerPoint/run state.
- Reopening reconstructs widgets from the independent model. Raw-command draft,
  active source, and valid selected-item identities survive; window geometry,
  list scroll positions, and invalid selections do not.
- Refreshing an existing view, including from `TO SCANS` or `TO QUEUE`, must not
  steal keyboard focus.
- All runner, mutation, and shared-state callbacks must tolerate missing or
  invalid figure/widget handles. They update the model first and render only
  through a guarded optional refresh.

### State Ownership and Selection

- `smaux.scans` remains the compatibility-facing scan library and `smaux.smq`
  remains the compatibility-facing pending queue.
- The model also owns the raw-command draft, active insertion source, selected
  library and pending-item identities, queue phase, running item, and
  stop-after-current state. Figure appdata and widget properties are not the
  source of truth for these values.
- Assign each library and pending entry a stable session-local identity in model
  metadata parallel to the compatibility arrays. Do not inject GUI-only IDs into
  scan structs or raw-command payloads. Equal-valued duplicate entries must
  remain independently selectable and movable.
- Before every model operation or render, reconcile direct external changes to
  `smaux.scans` and `smaux.smq` against the last mirrored sequences. Preserve
  identities for matched entries in occurrence order and assign new identities
  to unmatched entries. This keeps direct compatibility-array mutation supported
  while making duplicate reconciliation deterministic.
- Queue contains pending items only. The item removed for execution is stored as
  the separate running item and is never silently reinserted.
- Selection follows item identity when the model changes. If the selected item
  is removed, select the nearest valid item or the empty state; never retain an
  out-of-range numeric widget index.
- Available Scans and Queue remain single-select.

### Scan Library, Pending Queue, and Raw Commands

- Open Scans continues to accept a folder or selected MAT files containing
  `smscan`, `scan`, or cell/struct `scans` payloads. Invalid entries are skipped;
  accepted scans are sanitized for the bridge before appending.
- Save Scans continues to normalize `consts` and `finish`, sanitize names, avoid
  collisions, and write one `smscan` MAT file per library entry in a timestamped
  folder under the experiment root.
- Each insertion action works from either Available Scans or Raw Commands.
  `Insert at Top` prepends, `Insert After Selected` inserts after the selected
  pending item, and `Add to End` appends. With an empty queue, all three create
  the first item.
- A successful Raw Commands insertion preserves the exact multiline text in the
  queued payload and clears the draft only after the model mutation succeeds.
  Empty or whitespace-only draft behavior remains unresolved below.
- `Move Up` and `Move Down` are boundary no-ops. `Remove` and Delete remove only
  the selected pending item without confirmation.
- Delete in Available Scans removes only the selected library entry and then
  revalidates selection by identity.
- Double-clicking an available or queued scan copies it into `smscan` and opens
  `smgui_small`; it never inserts or starts the scan. Editing a queued raw item
  replaces any existing Raw Commands draft with the queued item's exact text and
  removes that pending item, matching current overwrite behavior.
- Queued raw commands remain supported after Console is removed. They execute
  line-by-line with `evalin("base", ...)` on the client; `smeval(...)` remains the
  explicit engine-worker path. Because arbitrary client code is synchronous,
  stop requests take effect after the current raw-command item returns.
- `TO SCANS` and `TO QUEUE` normalize scan constants and finish actions, append
  to the independent model, and summon an absent queue view or refresh the
  existing view without focus theft.
- File-menu Open Scans, Save Scans, and Edit Rack remain functional. Edit Rack
  is unavailable for the entire active scan lifecycle, including startup,
  finish actions, and final saving.

### Shared State and Notifications

- Data path, run number, and PowerPoint state remain owned exclusively by the
  existing shared services. Both GUIs receive broadcasts; neither caches a
  conflicting per-view value.
- Queue and scan GUI runs pass an empty filename to `engine.run`; the engine owns
  collision-free filenames and run-number advancement.
- Run number accepts empty or a finite value in `[0, 999]`. Invalid input shows
  an error and clears the shared manual value. The shared run service rounds a
  valid finite value to the nearest integer before using it.
- Notifications display the engine-level Slack account only. The empty label is
  exactly `Account not provided`. Notification failures are reported through
  `experimentContext` and never halt queue advancement.
- A normally completed or gracefully stopped scan sends the saved PNG and MAT
  artifacts, duration, completion/stop state, and stop reason through the
  existing notification service. Raw-command items send no scan notification.
  Cache a successfully resolved Slack user ID through the engine service.
- Remove the dormant per-scan Slack-account override. It is not part of the
  authored scan contract.

### Execution, Stops, and Errors

- Start with an empty queue is a no-op. Start is also an early silent no-op when
  the queue phase is not idle or `engine.isScanInProgress` is true; this check
  occurs before any item or selection mutation.
- Queue scans call `engine.run(scan, "", "turbo")`; the scan GUI continues to use
  safe mode. Items run in pending order. The active item is removed atomically
  from pending and shown separately before execution begins.
- The active item remains consumed after success, stop, or error. Later pending
  items are preserved unless they subsequently start.
- Stop Now, Escape, confirmed scan-figure close, and instrument-requested safety
  stops use the request-scoped graceful-stop path: finish actions run, partial
  data and the reason are saved, queue execution halts, and pending items remain.
- Stop Queue records stop-after-current without interrupting the active item.
  When that item finishes, queue execution returns to idle with pending items
  untouched.
- A raw-command item cannot be interrupted by the engine stop path. The exact
  Stop Now and Stop Queue behavior when MATLAB can dispatch their callbacks is
  unresolved below and must be decided before those controls are implemented.
- A declined Stop Now confirmation changes no state.
- Acquisition, communication, client, or finalization errors must return control,
  clear running/stop phase, leave later pending items stable, and report the
  error. Rendering or notification failures do not consume another item.
- Run/Start callbacks remain interruptible so GUI stop and close callbacks can
  execute. Duplicate Start protection comes from model/engine state, not from
  making the executing callback noninterruptible.
- Preserve the current timing exactly until the unresolved decision below is
  changed: pause three seconds after every normally returned scan item, including
  the final item; do not pause after a raw-command item or a stop-requested scan.
  A stop request received during that pause prevents the next pending item from
  starting.

The target Stop Now control requires a public, request-scoped engine stop API.
Do not mutate engine-private flags or synthesize a plot-figure callback to stop
a run.

## Queue State Matrix

| Phase | Start | Pending edits | Stop Now | Stop Queue | Closing queue view |
|---|---|---|---|---|---|
| Idle | Starts first pending item; empty queue is a no-op | Allowed | Disabled | Disabled | Deletes only the view |
| Running scan | Silent no-op | Insert, move, remove, and edit are allowed | Confirms, then requests graceful stop | Sets stop-after-current | Execution continues without a view |
| Running raw command | Silent no-op | Allowed when MATLAB can dispatch the callback | Unresolved | Unresolved | Execution continues without a view |
| Between scan items | Silent no-op | Allowed | Halts before another item starts | Halts before another item starts | Execution continues without a view |
| Stopping after current | Silent no-op | Allowed | Escalation behavior is unresolved | Disabled and labeled `Stopping After Current...` | Execution continues without a view |
| Stopping now | Silent no-op | Allowed | Disabled after request is sent | Disabled | Stop/final save continue without a view |

Every exit from a non-idle phase -- normal completion, stop, error, or engine
replacement failure -- must leave the model in a defined phase and make a later
`sm` render the same state.

## Intentional Current-to-Target Changes

| Current GUIDE behavior/control | Programmatic replacement |
|---|---|
| GUIDE `.fig` construction | MATLAB code creates one resizable singleton figure |
| `RUN` and `PAUSE` | Green `Start`, red `Stop Now`, amber `Stop Queue`; Pause removed |
| One context-dependent enqueue button | Explicit `Insert at Top`, `Insert After Selected`, and `Add to End` |
| Running item disappears from Queue with no dedicated display | Separate `Running: <name>` display; Queue contains pending items only |
| Queue Edit button | Double-click for scans; queued raw edit returns text to the draft |
| Delete-key-only pending removal | Add `Move Up`, `Move Down`, and `Remove`; retain Delete |
| Legacy notification-user list and dormant per-scan override | Read-only engine Slack account |
| Console and queued Raw Commands | Remove Console but retain queued Raw Commands and client-base execution |
| AutoIncrement, QuickSave, Save Now, Figure, Priority, and Comments | Remove; shared engine/services retain the supported behavior |
| Queue figure owns callback handles used during execution | Figure is a disposable view; runner and model survive its closure |
| Open Scans, Save Scans, and Edit Rack | Preserve as functional File-menu actions |

## Regression Acceptance Matrix

These cases are release gates, not suggestions. Automated tests should cover
model and callback behavior; dialog and visual cases may use a documented manual
check until a deterministic harness exists.

| ID | Starting state and action | Required result | Validation |
|---|---|---|---|
| Q-LIFE-01 | Call `sm` before `smready` | Throw `sm:MissingEngine`; create no figure/model fragment | Automated |
| Q-LIFE-02 | Call `sm` twice | Same valid singleton is returned/raised; no duplicate figure | Automated |
| Q-LIFE-03 | Close and reopen while idle | Library, pending queue, draft, source, and valid selections survive | Automated |
| Q-LIFE-04 | Close during a scan, then reopen from a timer or interruptible GUI callback | Scan/queue continue; reopened view shows running and pending state | Automated plus manual timing |
| Q-LIFE-05 | Close during a scan, then call `sm` from the Command Window after the synchronous runner returns | Reopened view shows the final idle/pending state | Automated |
| Q-LIFE-06 | Close and reopen from a timer or interruptible GUI callback while stopping after current | Phase, pending items, disabled state, and `Stopping After Current...` label survive | Automated |
| Q-LIFE-07 | Close immediately after accepted Stop Now, then reopen after the synchronous runner returns | Graceful stop, finish actions, final save, and pending preservation complete; reopened view is idle | Automated |
| Q-MODEL-01 | Insert either source using all three actions | Exact top/after/end order, including empty queue | Automated |
| Q-MODEL-02 | Move at middle/boundaries; remove by button/Delete | Correct identity moves/removes; boundaries are no-ops | Automated |
| Q-MODEL-03 | Mutate queue around selected item | Selection follows identity or nearest valid item | Automated |
| Q-MODEL-04 | Select one of two equal-valued duplicate entries, then mutate the model | Stable per-entry identity preserves the intended duplicate | Automated |
| Q-MODEL-05 | Insert, move, remove, or edit pending items while a scan runs | Only requested pending entries change; running item remains separate | Automated |
| Q-MODEL-06 | Press Delete in Available Scans | Only the selected library entry is removed; selection revalidates | Automated |
| Q-MODEL-07 | Append, delete, or replace entries directly in either compatibility array | Model reconciles stable IDs deterministically; valid selection survives | Automated |
| Q-EDIT-01 | Double-click library or queued scan | Copy opens in scan editor; no library/pending insert, start, or mutation | Automated |
| Q-EDIT-02 | Edit queued raw item | Item is removed and exact text becomes the draft | Automated |
| Q-EDIT-03 | `TO SCANS`/`TO QUEUE` with queue view open | Model updates and view refreshes without focus theft | Automated focus probe |
| Q-EDIT-04 | Insert a multiline raw draft using each insertion action | Exact text is queued and draft clears only after successful insertion | Automated |
| Q-EDIT-05 | Edit a queued raw item while the draft is nonempty | Queued exact text replaces the draft and only that pending item is removed | Automated |
| Q-EDIT-06 | `TO SCANS`/`TO QUEUE` with no queue view | Model mutates first and exactly one singleton view is created | Automated |
| Q-FILE-01 | Open each supported MAT payload form | Valid scans append in file order; invalid entries skip | Automated with temp files |
| Q-FILE-02 | Save duplicate/invalid scan names | Normalized unique `smscan` files are written under experiment root | Automated with temp folder |
| Q-SHARED-01 | Change path/run/PPT in either GUI | Shared state and both views agree; engine receives empty filename | Automated |
| Q-SHARED-02 | Enter fractional, boundary, empty, and invalid run values | Finite `[0,999]` values round through the shared service; invalid clears | Automated |
| Q-RUN-01 | Start empty, during active scan, or during inter-item phase | Early silent no-op; queue and selection remain unchanged | Automated |
| Q-RUN-02 | Run scans and raw commands in sequence | Exact order; scans use turbo; raw lines evaluate once on client | Automated |
| Q-RUN-03 | An active item completes normally | Running clears; next pending starts once after the specified cadence, or phase becomes idle after the queue drains | Automated |
| Q-RUN-04 | A raw command throws | Runner returns, phase clears, failed item stays consumed, and later pending remains | Automated fault injection |
| Q-RUN-05 | Inspect Start/Run callback dispatch during execution | Executing callback remains interruptible; duplicate action is canceled by state guard | Automated callback probe |
| Q-STOP-01 | Decline then accept Stop Now | Decline is no-op; accept saves partial result/reason and preserves pending | Automated stop path plus dialog check |
| Q-STOP-02 | Request Stop Queue | Current completes; no later item starts; pending remains | Automated |
| Q-STOP-03 | Escape, confirmed plot close, or safety stop | Same graceful metadata/save behavior; queue halts | Existing stop regressions |
| Q-STOP-04 | Request either stop during the three-second post-scan pause | No next item starts; all pending items remain | Automated timer callback |
| Q-STOP-05 | Request either stop during a raw command | Behavior matches the resolved raw-stop policy; an accepted halt never starts a later item | Automated interruptible callback after decision |
| Q-ERROR-01 | Acquisition/client/save error | Runner returns, phase clears, failed item stays consumed, later pending remains | Automated fault injection |
| Q-ERROR-02 | Slack send fails | Warning is reported and next pending item still starts | Automated mock |
| Q-NOTIFY-01 | Complete and gracefully stop scans; run a raw command | Scan notifications include artifacts/duration/state/reason, resolved ID caches, raw sends none | Automated mock |
| Q-REBIND-01 | `smready` during an engine scan, raw command, or between-item pause, then while idle | Every active call throws before mutation; idle rebind preserves queue model/shared state | Automated |
| Q-RACK-01 | Observe Edit Rack across full run lifecycle | Disabled through startup/acquisition/finish/save; restored afterward | Automated slow-finish probe |
| Q-VIEW-01 | Refresh existing view from external model change | No focus theft; controls reflect model; no stale-handle error | Automated focus/handle probe |
| Q-VIEW-02 | Close and reopen after changing shared path/run/PPT state | Recreated view reflects unchanged shared state | Automated |
| Q-STATE-01 | Render every queue phase | Start/stop enabled states and `Stopping After Current...` label match the state matrix | Automated |
| Q-VIS-01 | Render minimum/default/tall/wide sizes | Geometry satisfies the visual contract below | Geometry assertions plus manual review |

Existing local coverage includes `test_gui_run_buttons_ignore_active_scan.m`
and `test_queue_user_cancel_stops_queue.m`, plus measurement-engine Escape,
close, error, lifecycle, and final-save tests. The replacement should add focused
tests named for singleton close/reopen, model insert/move/remove, raw-command
execution, shared-state sync, stop controls, error recovery, between-item Start
guard, scan-editor focus, scan-library I/O, and layout contract. The `tests/`
folder is local-only, so this matrix is the durable tracked acceptance record.

## Visual Regression Contract

- Default size is 1100 x 800 pixels within 25 pixels per dimension. The resize
  clamp never permits width below 850 pixels or height below 600 pixels. The
  window is resizable in both dimensions.
- At minimum, default, 150-percent width, and 150-percent height, no control may
  overlap, clip outside its parent, acquire negative dimensions, or become
  unusable.
- The compact top strip remains 60--80 pixels high. Save, PowerPoint, and
  Notifications remain within three percentage points of 40, 35, and 25
  percent of its usable width.
- Schedule absorbs all remaining growth. Available Scans and Queue keep equal
  operational width within two pixels. Available Scans and Raw Commands remain
  within three percentage points of the 80/20 vertical split.
- The three insertion actions remain visually distinct, separated enough to
  avoid misclicks with at least eight pixels between controls, and above the
  vertical midpoint.
- Running item, pending queue, active insertion source, empty states, and each
  queue phase are visibly distinguishable without relying on color alone.
- Start is green, Stop Now red, and Stop Queue amber. Disabled and
  stopping-after-current states remain legible.
- Long paths and PowerPoint filenames may be shortened visually, but their full
  value remains available by tooltip and the model value is unchanged. Long scan
  name and Slack-account presentation remains an explicit decision below.
- Geometry tests assert containment, ordering, proportions, and enabled states;
  they do not lock the implementation to screenshot pixels. The numeric values
  above are regression tolerances around the confirmed approximate layout, not
  a requirement for exact screenshot matching.

## Removed Areas

- Comments
- AutoIncrement
- QuickSave
- Save Now
- Figure-number PowerPoint control
- Pause
- Legacy Notifications user list
- Priority PowerPoint controls
- Console
- Dead Open Rack and Save Rack actions

Removing Console does not remove queued Raw Commands. Open Scans, Save Scans,
and Edit Rack are retained. Controls whose present callbacks are inert are not
functional compatibility requirements.

## Implementation Reference Map

- `code/smbridge/sm.m`: current GUIDE entry point, widget tags, and callback
  dispatch.
- `code/smbridge/sm_Callback.m`: current scan-library, pending-queue, raw-command,
  shared-state, run, notification, and keyboard behavior.
- `code/smbridge/smgui_small.m`: scan editor plus `TO SCANS`, `TO QUEUE`, and
  direct safe-mode Run behavior.
- `code/smbridge/smready.m`: engine binding and GUI launch lifecycle.
- `code/smbridge/shared/`: shared data-path, PowerPoint, and run-number state.
- `code/sm2/@measurementEngine/`: run-state, turbo execution, stop metadata,
  error cleanup, finish actions, and final saving.
- `docs/SMBRIDGE_GUI_ARCHITECTURE.txt`: current bridge architecture and current
  versus planned GUI boundary.
- `tests/test_gui_run_buttons_ignore_active_scan.m` and
  `tests/test_queue_user_cancel_stops_queue.m`: existing queue-facing regression
  coverage; the acceptance matrix above defines the additional required tests.

## Unresolved Decisions

- Detailed list labeling, keyboard shortcuts, empty-state text, presentation of
  long scan names and Slack accounts, and whether to add confirmation before
  deleting an Available Scan. Until resolved, preserve immediate deletion.
- Whether an empty or whitespace-only Raw Commands draft is rejected, ignored,
  or queued. Do not silently trim a nonempty multiline draft.
- How Stop Now and Stop Queue behave during a synchronous raw-command item. The
  engine stop API cannot interrupt arbitrary client `evalin`; the decision must
  define confirmation, latching, and the next-item rule when a callback can run.
- Whether scan-library and pending-queue state should persist across a MATLAB restart or remain session-only.
- Whether to retain, shorten, or remove the current three-second pause after a
  completed scan item. Preserve it until this is resolved.
- Whether Stop Now may escalate a prior Stop Queue request while the current
  scan is still running.
