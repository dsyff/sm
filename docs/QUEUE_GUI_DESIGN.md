# Programmatic Queue GUI Design

Status: implemented programmatic queue-GUI design and binding regression
contract. Confirmed decisions remain binding; newly discovered behavior gaps
must be recorded under **Unresolved Decisions** before changing the contract.

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

## Reconciled Legacy Baseline (pre-replacement)

The current baseline was re-audited on 2026-08-24 against `README.md`,
`README_SHORT.md`, `docs/SMBRIDGE_GUI_ARCHITECTURE.txt`,
`docs/MEASUREMENT_ENGINE_ARCHITECTURE.md`, the current bridge/engine code, and
the GUI/lifecycle commits through `ad66921`.

- The replaced queue GUI was the GUIDE-based `sm`/`sm_Callback` path. The
  current `sm` entry point constructs the singleton entirely in MATLAB code.
- The current scan GUI's scrollable finish panel, focus-preserving numeric edits,
  vertical resizing, and active-scan Edit Rack lock remain scan-GUI behavior.
  They are compatibility dependencies, not queue-layout constraints.
- Preserve the recent lifecycle fixes: Run callbacks remain interruptible,
  duplicate starts are rejected by state guards, the engine remains active
  through startup/finish/final save, and graceful stops preserve pending queue
  entries.
- Acquisition-loop and final dirty-flush failures handled by the engine are
  graceful stops with finish actions, partial final saving, stop metadata, and
  notification. They are distinct from errors propagated to the queue callback.

## Architecture

- Keep `sm` as the public queue-GUI entry point so `smready` and existing scripts do not change.
- Replace the GUIDE construction path and binary `.fig` dependency with programmatic `figure`, `uipanel`, and `uicontrol` construction.
- Keep canonical scan-library, pending-queue, running-item, and queue-control state outside the queue figure in a GUI-independent state owner.
- Treat the queue GUI as a disposable view of that state. Closing the figure must not stop execution, clear state, or otherwise affect the scan/queue system.
- A plain `sm` call creates and attaches a queue GUI when none exists, or raises the existing queue GUI when one is already open. At most one queue GUI may exist.
- `sm` requires an initialized measurement engine. Before `smready(...)`, it throws `sm:MissingEngine` with a direct setup instruction instead of opening a partial GUI.
- Preserve the `smaux.sm` handle contract only as the currently attached view contract required by existing callbacks and shared GUI state helpers.
- Make the window resizable. Start near 924 x 800 pixels with a practical minimum
  near 724 x 600 pixels. Do not persist geometry across MATLAB sessions initially.
- Queue scans continue to use turbo mode; direct runs from the scan GUI continue to use safe mode.
- Repeated Start clicks during an active scan remain silent no-ops before any queue or scan state changes.
- Do not globally disable the queue GUI merely because a scan is active. In the
  normal recipe configuration, acquisition runs in the engine worker while the
  client GUI remains interactive. Keep every model, library, file, shared-state,
  and editor action enabled unless this contract identifies a specific unsafe
  state. Duplicate Start, phase-inapplicable stops, and Edit Rack are the narrow
  exceptions.
- A safe-mode scan started outside the queue is the explicit exception: fully
  disable queue-GUI interaction for its complete active lifecycle. Do not clear
  or mutate queue/library/view-model state while locked.
- Expose authoritative public read-only, observable engine properties
  `activeRunMode` (`""`, `"safe"`, or `"turbo"`) and `activeRunPhase` (`"idle"`,
  `"startup"`, `"acquiring"`, or `"finalizing"`). Set and clear them on every
  success/error cleanup path. The queue state listens to these properties; it
  must not infer safe mode from `isScanInProgress` or queue ownership.
- Keep the existing synchronous `engine.run` contract. Closing the queue GUI does not interrupt execution, but a Command Window `sm` call cannot execute until MATLAB returns from the active scan callback; do not expand this project into an asynchronous engine rewrite.
- If `smready(...)` is called while an engine scan is active or the queue phase is
  non-idle, throw `smready:ScanActive` before replacing state. This includes a
  raw command and the brief between-item callback-dispatch transition, even when
  `engine.isScanInProgress == false`. When idle, rebind to the new engine while
  preserving the scan library, pending queue, raw-command draft, and shared
  Save, PowerPoint, and run state.
- Scan-library, pending-queue, and runtime state are MATLAB-session-only. Do not
  automatically save, restore, or resume a queue across MATLAB restarts. Open
  Scans and Save Scans remain the explicit persistence path for the scan library.

## Shared Save and PowerPoint State

The scan and queue GUIs must be two views of the same state. They must not maintain independent filename, data-path, run-number, or PowerPoint state.

- Initialize the existing shared services with `smdatapathEnsureGlobals`, `smrunEnsureGlobals`, and `smpptEnsureGlobals` after `smbridgeAddSharedPaths`.
- Register the queue GUI as source `main` with `smdatapathRegisterGui`, `smrunRegisterGui`, and `smpptRegisterGui`.
- Creating or recreating either GUI registers its handles and then applies the
  canonical shared state; widget defaults must never overwrite or rebase that
  state. The shared PowerPoint initializer owns the one-time default
  `<experiment root>/log.ppt` value.
- Read state only through the matching `*GetState` functions.
- Write state only through the matching `*UpdateGlobalState` functions, then refresh the source GUI with the matching `*ApplyStateToGui("main")` call. Updates must continue to broadcast to the scan GUI.
- Both GUIs pass an empty filename to `engine.run`. The engine remains responsible for collision-free `NNN_<scan-name>.mat` generation and shared run-number advancement.
- PowerPoint state is global and is read by the engine during final saving. There is no per-scan PowerPoint state.
- Keep Path and Run # editable during turbo queue execution. The active scan
  retains the data path and run number resolved at its start; edits apply to the
  next scan. If Run # changes after the active scan captured its value, that user
  edit wins and completion must not overwrite it with the active scan's automatic
  increment. When no intervening edit occurred, normal increment continues.
- Keep PowerPoint enabled/file controls live during turbo queue execution.
  Snapshot the shared PowerPoint state exactly once when finalization begins; the
  last pre-finalization values govern that scan, and later edits govern future
  scans.

## Layout

- Use one compact top strip, approximately 70 pixels high:
  - Save: 40 percent of the strip width.
  - PowerPoint: 35 percent.
  - Notifications: 25 percent.
- Let Schedule use all space below the compact top strip and absorb all additional window height and width.
- Give Available Scans and Queue equal width. At the default 924-pixel window
  width, keep each approximately 374 pixels wide, preserving the requested
  20-percent reduction from the original 468-pixel allocation.
- Divide the left source area vertically: Available Scans receives 80 percent and Raw Commands receives 20 percent.
- Center the shared queue-insertion buttons in a 120--121-pixel lane between the
  source area and Queue, leaving approximately 12 pixels around their 96-pixel
  width. Keep them above the vertical midpoint because Available Scans is the
  most frequently used source.
- Use 56-pixel-high insertion buttons with 16-pixel vertical gaps. Clamp the
  stack upward as needed so it remains contained at minimum window height.
- In the Queue pane, place the one-line status first, then one horizontal
  execution-control row, then the pending list. Order that row `Start`, `Stop
  Queue`, `Stop Now`. Give all three the same responsive size, up to 88 by 32
  pixels. Left-align `Start`, center the compact `Stop Queue`, and right-align
  destructive `Stop Now`. Keep at least 15 pixels between adjacent controls at
  minimum width and distribute substantially more space when available.
- Do not add an Available Scans search or filter in the first replacement. Give
  that vertical space to the list.

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
- Keep the account on one line. Allow natural clipping at the minimum window
  size, do not wrap or add manual ellipses, and expose the complete account in a
  tooltip.

Code audit result: normal configuration has no per-scan Slack authoring path. `recipe.slack_notification_account_email` is resolved by `smready` into `engine.slack_notification_settings.account_email`. Remove the dormant compatibility branch that reads a manually supplied `scan.slack_notification_account_email`; no GUI, demo, or scan-building path creates that field.

## Schedule and Queue Interaction

- Retain Available Scans, Raw Commands, Queue, and their edit workflows.
- The active insertion source defaults to Available Scans on first launch and
  thereafter is the most recently selected Available Scans or Raw Commands panel.
- Highlight the active source panel and show a small changing label above the insertion controls.
- Preserve the raw-command draft, active source, and selected scan/queue item identities when the view is closed. Revalidate stored selections when the model changes; do not preserve list scroll positions or window geometry.
- Available Scans and Raw Commands share three compact rightward insertion
  actions whose labels point toward Queue:
  - `Top >>` (insert at top)
  - `After >>` (insert after selected)
  - `End >>` (add to end)
- When Queue is nonempty with no selected pending item, disable `After >>`; its
  direct or stale callback is a silent no-op. `Top >>` and `End >>` remain
  available. With an empty Queue, all three actions are valid.
- Show execution state in one line above Queue using exactly `Idle`, `Running:
  <name>`, `Stopping After Current: <name>`, `Stopping Now: <name>`, or
  `Finalizing: <name>`. Do not add elapsed time or an ETA. Keep the line unwrapped
  with the complete value in its tooltip. Queue itself contains only pending
  items.
- Empty Available Scans and Queue lists display muted, nonselectable placeholders
  `No scans loaded` and `Queue is empty`. An empty Raw Commands editor displays
  the prompt `Enter MATLAB commands...`; the prompt is not draft content.
- Allow insert, delete, reorder, and edit operations on pending items during execution.
- Add compact `Move Up`, `Move Down`, and `Remove` controls below Queue; retain Delete-key removal.
- Keep both lists semantically single-select. A classic MATLAB listbox may use
  `Max=2` only while the model deliberately has no selection, because that is
  the supported way to render `Value=[]`; its callback immediately collapses
  any user selection to one identity and restores `Max=1`. Removing one pending
  item takes effect immediately without confirmation; do not add a bulk Clear
  Queue control.
- Available Scans rows display only the scan name. Pending Queue rows display a
  compact one-based position followed by the scan name; raw-command rows display
  the position, `[CMD]`, and the first nonblank line. Do not add extra columns.
  Keep every row on one line with natural clipping; do not wrap or add manual
  ellipses. The list tooltip displays the complete text of the selected row.
- Retain immediate Delete-key removal of the selected Available Scan without a
  confirmation dialog.
- A successful insertion selects the new pending item and scrolls it into view.
  A moved item remains selected and visible. After a user removes an Available
  Scan or pending item, select the item now at the same row, or the previous last
  item when the removed row was last; select nothing when the list becomes empty.
- Double-clicking an available or queued scan opens it in the scan editor. Double-click never inserts or starts a scan.
- With focus in Available Scans or Queue, Delete removes, Enter edits, and
  Ctrl+Up/Ctrl+Down moves the selected pending item. Move shortcuts are no-ops
  outside Queue. Do not assign keyboard shortcuts to Start, Stop Now, or Stop
  Queue. Enter in Raw Commands continues to insert a newline.
- `TO SCANS` and `TO QUEUE` in the scan GUI update the independent state and then summon `sm` if the queue GUI is absent. If it already exists, refresh the same singleton view without stealing keyboard focus.

## Execution Controls

- Replace Run and Pause with:
  - Green `Start`
  - Red `Stop Now`
  - Amber `Stop Queue`
- Remove Pause entirely.
- `Stop Now` uses a modal confirmation titled `Stop Current Scan?` with the exact
  message `Stop the current scan now? Finish actions will run, partial data will
  be saved, and the queue will stop.` Its buttons are `Stop Now` and `Cancel`,
  with `Cancel` as the default. Acceptance gracefully stops the active scan, runs
  finish actions, saves partial data and stop metadata, and halts queue processing.
- `Stop Queue` requires no confirmation. It lets the current scan finish and then halts queue processing.
- Both stop actions leave every pending item in Queue.
- When idle, both stop buttons are disabled. Start is disabled when Queue has no
  pending item and enabled when an idle Queue is nonempty; its direct callback
  retains the silent empty/active guard.
- After Stop Queue is requested, change its label to `Stopping After Current...` and disable it until execution ends.
- While the current item is a scan, Stop Now remains enabled after Stop Queue is
  requested. A confirmed click escalates the deferred request to stopping now.
  Stop Now remains disabled throughout a raw-command item.
- Once acquisition has ended and finish actions or final saving are running,
  display `Finalizing: <name>`, disable Stop Now, and keep Stop Queue enabled. A
  previously queued or stale Stop Now callback in that phase silently latches
  stop-after-current without showing its confirmation dialog.
- Closing the queue GUI is always allowed and has no queue or scan side effects. If execution continues without a view, a later `sm` call recreates the singleton view and reflects the current state.
- During an active safe-mode scan, disable every queue-GUI menu and control, dim
  the content, and place the noninteractive message `Safe-mode scan active —
  queue controls disabled` above it. The operating-system window Close control
  remains available and retains the normal detach-only behavior.
- A dispatched `sm` call during safe mode creates the singleton directly in its
  disabled state when absent, or raises the existing disabled view. When safe
  mode ends, restore each control from current model/state rules without raising
  the window or stealing focus. Preserve library, pending Queue, draft,
  selections, and shared state; remain idle and never auto-start pending work.

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
- Successful user insertion selects and reveals the inserted pending identity.
  Moving an item preserves and reveals that identity. User removal from either
  list selects the identity now at the removed row, or the previous final
  identity when necessary, and leaves no selection when the list is empty.
- When the runner consumes the first pending item, preserve any different
  selected pending identity. If the consumed item was selected, select and reveal
  the new first pending item, or leave no pending selection when Queue is empty.
- Available Scans and Queue remain single-select.

### Scan Library, Pending Queue, and Raw Commands

- Open Scans continues to accept a folder or selected MAT files containing
  `smscan`, `scan`, or cell/struct `scans` payloads. Invalid entries are skipped;
  accepted scans are sanitized for the bridge before appending.
- Duplicate scan names remain distinct Available Scans entries. Do not
  deduplicate or rename them in memory; their stable session-local identities
  distinguish definitions that happen to share a display name.
- Folder import considers only top-level `*.mat` files, never descendant folders,
  and processes them in deterministic case-insensitive filename order. Preserve
  the stored order of scans within each accepted payload.
- After every noncanceled Open Scans attempt, send one plain-text summary through
  `experimentContext.print(...)` with the loaded-scan and rejected-input counts.
  Rejections include unreadable files, unsupported payloads, and invalid scan
  entries. Mixed success shows no dialog. If zero scans were accepted, also show
  one modal titled `No Valid Scans`; do not mutate the existing library.
- Sort explicitly selected MAT files case-insensitively by full path before
  processing them, then preserve scan order inside each file payload. After a
  successful import, select and reveal the first newly appended Available Scan.
  `TO SCANS` selects and reveals its appended scan without stealing keyboard
  focus.
- Save Scans continues to normalize `consts` and `finish`, sanitize names, avoid
  collisions, and write one `smscan` MAT file per library entry in a timestamped
  folder under the experiment root.
- Disable Save Scans when the scan library is empty; a direct or stale callback
  in that state is a silent no-op. After a successful export, send exactly one
  plain-text `Saved <N> scans to <path>.` message through
  `experimentContext.print(...)` and show no completion dialog.
- Every Save Scans invocation creates a new export folder. If
  `scans_<timestamp>` already exists, append the first available numeric suffix
  such as ` (1)`; never merge a new export into an existing folder.
- Save Scans snapshots the library at callback entry. If folder creation,
  normalization, or writing fails, stop at the first failure, keep successfully
  written files and the partial export folder, and leave the in-memory library
  unchanged. Print the partial count/path plus the full plain-text report through
  `experimentContext.print(...)` and show one concise failure modal. Do not
  delete or roll back successful output.
- Each insertion action works from either Available Scans or Raw Commands.
  `Top >>` prepends, `After >>` inserts after the selected pending item, and
  `End >>` appends. With an empty queue, all three create the first item. With a
  nonempty Queue and no pending selection, `After >>` is disabled and a direct
  invocation is a silent no-op; it never falls back to the first item or the end.
- A successful Raw Commands insertion preserves the exact multiline text in the
  queued payload and clears the draft only after the model mutation succeeds.
  While Raw Commands is the active source, disable all three insertion controls
  when the draft is empty or whitespace-only. A direct or programmatic insertion
  callback in that state is a silent no-op and leaves the draft unchanged. Never
  trim a nonempty draft before queuing it.
- `Move Up` and `Move Down` are boundary no-ops. `Remove` and Delete remove only
  the selected pending item without confirmation.
- Delete in Available Scans removes only the selected library entry and then
  revalidates selection by identity.
- Double-clicking an available or queued scan copies it into `smscan` and opens
  `smgui_small`; it never inserts or starts the scan. Editing a queued raw item
  replaces any existing Raw Commands draft with the queued item's exact text and
  removes that pending item, matching current overwrite behavior.
- During a turbo queue scan, keep scan viewing/editing and `TO SCANS`/`TO QUEUE`
  available. The scan editor's Run and Edit Rack actions remain unavailable
  because the engine is active; all other editor mutations remain local until an
  explicit transfer action.
- Queued raw commands remain supported after Console is removed. They execute
  line-by-line with `evalin("base", ...)` on the client; `smeval(...)` remains the
  explicit engine-worker path. Stop Now is disabled throughout a raw-command
  item. Stop Queue remains enabled and latches stop-after-current if MATLAB can
  dispatch its callback. If the command does not yield, the click waits until
  the command returns; the runner then services pending callbacks before it may
  start another item.
- `TO SCANS` and `TO QUEUE` normalize scan constants and finish actions, append
  to the independent model, and summon an absent queue view or refresh the
  existing view without focus theft.
- File-menu Open Scans, Save Scans, and Edit Rack remain functional. Edit Rack
  is unavailable for every non-idle queue phase, including raw commands and the
  between-item transition, and for the entire active engine-scan lifecycle,
  including startup, finish actions, and final saving.
- The scan editor's Run action is likewise unavailable for every non-idle queue
  phase, so an interruptible raw command or between-item callback cannot nest an
  external safe-mode scan inside the queue runner.
- Open Scans and Save Scans remain enabled during acquisition, raw-command
  execution when callbacks can dispatch, stopping, and finalization. They operate
  only on the independent scan library and must not stop, pause, or mutate the
  running item or pending Queue. A file-operation failure is isolated from queue
  execution.
- Retain the native modal file/folder dialogs. During a turbo queue scan, worker
  acquisition continues while a dialog is open, but client plotting, dirty-data
  acknowledgement, and the final handshake may wait until it closes. Resume
  normal polling afterward; do not replace these dialogs with a custom picker.

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

- Start is disabled in an empty Queue view, and a direct invocation with an empty
  queue is a silent no-op. Start is also an early silent no-op when the queue
  phase is not idle or `engine.isScanInProgress` is true; these checks occur
  before any item or selection mutation.
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
- A confirmed Stop Now after Stop Queue replaces stop-after-current with the
  request-scoped graceful stop-now request. The scan runs finish actions and
  final saving, and no later pending item starts.
- A raw-command item cannot be interrupted by the engine stop path. Stop Now is
  therefore disabled for the entire raw-command phase. Stop Queue remains
  enabled: its callback sets stop-after-current, and the runner halts before the
  next pending item. If the command does not yield, the callback is serviced
  immediately after it returns and before the next-item decision.
- During finish actions or final saving, Stop Now cannot interrupt completed
  acquisition and is disabled. Stop Queue remains available to halt after the
  finalizing item. A stale Stop Now invocation has that same stop-after-current
  effect and is a silent no-op with respect to the scan itself.
- During the between-item callback-dispatch transition, a stale invocation of
  either stop action silently latches a queue halt before the next item. Stop Now
  shows no confirmation because there is no current scan.
- A declined Stop Now confirmation changes no state.
- An error propagated from a raw command or from scan setup, client processing,
  finish actions, or finalization must first complete engine cleanup, then return
  the model to idle, clear the running/stop phase, consume the failed item, and
  preserve all later pending items. Do not rethrow from the GUI callback. Convert
  `getReport(ME, "extended", "hyperlinks", "off")` to plain text and pass it once
  through `experimentContext.print(...)`; do not emit it with `error`, `warning`,
  `fprintf`, or `disp`. Show a modal `Queue Item Error` dialog containing the
  stable item label and `ME.message`, even when the disposable queue view was
  closed before the failure.
- An acquisition-loop or final dirty-flush failure already converted by the
  engine into a graceful stop is not a propagated queue-callback exception. It
  runs finish actions, saves partial data and stop metadata, sends the normal
  stopped-scan notification, halts the queue, consumes the active item, and
  preserves later pending items. Do not add an error modal. Never classify it by
  parsing `stopMessage`.
- Rendering or notification failures do not consume another item. Notification
  failures remain nonfatal and do not halt queue advancement.
- Run/Start callbacks remain interruptible so GUI stop and close callbacks can
  execute. Duplicate Start protection comes from model/engine state, not from
  making the executing callback noninterruptible.
- Remove the legacy fixed three-second post-scan pause. After any item returns,
  service pending GUI callbacks before the next-item decision, then start the
  next pending item immediately if execution is still allowed. A stop request
  dispatched at that transition prevents the next item from starting.

The target Stop Now control requires a public, request-scoped engine stop API.
Do not mutate engine-private flags or synthesize a plot-figure callback to stop
a run.

## Queue State Matrix

| Phase | Start | Pending edits | Stop Now | Stop Queue | Closing queue view |
|---|---|---|---|---|---|
| Idle, Queue empty | Disabled; direct callback is a silent no-op | Allowed | Disabled | Disabled | Deletes only the view |
| Idle, Queue nonempty | Starts first pending item | Allowed | Disabled | Disabled | Deletes only the view |
| Running scan | Silent no-op | Insert, move, remove, and edit are allowed | Confirms, then requests graceful stop | Sets stop-after-current | Execution continues without a view |
| Running raw command | Silent no-op | Allowed when MATLAB can dispatch the callback | Disabled | Latches stop-after-current when its callback dispatches | Execution continues without a view |
| Between scan items | Silent no-op | Allowed | Silently halts before another item; no dialog | Silently halts before another item | Execution continues without a view |
| Stopping after current | Silent no-op | Allowed | Confirms and escalates when the current item is a scan; disabled for raw command | Disabled and labeled `Stopping After Current...` | Execution continues without a view |
| Stopping now | Silent no-op | Allowed | Disabled after request is sent | Disabled | Stop/final save continue without a view |
| Finalizing | Silent no-op | Allowed | Disabled; stale callback silently latches stop-after-current | Enabled and latches stop-after-current | Finalization continues without a view |
| External safe-mode scan | Disabled | Disabled, including all menus and shared-state controls | Disabled | Disabled | Deletes only the view; state and safe scan continue |

Every exit from a non-idle phase -- normal completion, stop, error, or engine
replacement failure -- must leave the model in a defined phase and make a later
`sm` render the same state.

## Intentional Current-to-Target Changes

| Current GUIDE behavior/control | Programmatic replacement |
|---|---|
| GUIDE `.fig` construction | MATLAB code creates one resizable singleton figure |
| `RUN` and `PAUSE` | Green `Start`, red `Stop Now`, amber `Stop Queue`; Pause removed |
| One context-dependent enqueue button | Explicit compact `Top >>`, `After >>`, and `End >>` actions |
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
| Q-MODEL-08 | Insert, move, and manually remove entries | Inserted item selects/reveals; moved identity remains selected/revealed; removal selects same row or previous final item | Automated |
| Q-MODEL-09 | Runner consumes the first pending item | A different selected identity survives; if consumed selection ran, new first selects/reveals or selection becomes empty | Automated |
| Q-EDIT-01 | Double-click library or queued scan | Copy opens in scan editor; no library/pending insert, start, or mutation | Automated |
| Q-EDIT-02 | Edit queued raw item | Item is removed and exact text becomes the draft | Automated |
| Q-EDIT-03 | `TO SCANS`/`TO QUEUE` with queue view open | Model updates and view refreshes without focus theft | Automated focus probe |
| Q-EDIT-04 | Insert a multiline raw draft using each insertion action | Exact text is queued and draft clears only after successful insertion | Automated |
| Q-EDIT-05 | Edit a queued raw item while the draft is nonempty | Queued exact text replaces the draft and only that pending item is removed | Automated |
| Q-EDIT-06 | `TO SCANS`/`TO QUEUE` with no queue view | Model mutates first and exactly one singleton view is created | Automated |
| Q-EDIT-07 | Make Raw Commands active with an empty or whitespace-only draft | Insertion controls disable; direct callback is a silent no-op and preserves the draft | Automated |
| Q-EDIT-08 | Use a nonempty Queue with no pending selection | `After >>` disables and its direct callback is a silent no-op; `Top >>` and `End >>` still work | Automated |
| Q-FILE-01 | Open each supported MAT payload form | Valid scans append in file order; invalid entries skip | Automated with temp files |
| Q-FILE-02 | Save duplicate/invalid scan names | Normalized unique `smscan` files are written under experiment root | Automated with temp folder |
| Q-FILE-03 | Import duplicate scan names | Every definition appends with a distinct stable identity and unchanged display name | Automated |
| Q-FILE-04 | Import a top-level folder containing valid, invalid, unreadable, and nested MAT files | Only top-level files are processed in case-insensitive name order; one plain summary reports accepted/rejected counts; mixed success has no modal | Automated with temp tree |
| Q-FILE-05 | Import inputs containing zero valid scans | Existing library is unchanged; one plain summary and one `No Valid Scans` modal appear | Automated plus dialog check |
| Q-FILE-06 | Render/call Save Scans with an empty library, then export a nonempty library | Empty action disables and stale call is a silent no-op; success prints one exact count/path message without a dialog | Automated |
| Q-FILE-07 | Import multiple explicitly selected files and use `TO SCANS` | Files process in case-insensitive full-path order; payload order is stable; first imported or appended scan selects/reveals without focus theft | Automated focus probe |
| Q-FILE-08 | Invoke Save Scans twice in one second | Second export uses a unique suffixed folder and never merges with the first | Automated with temp folder |
| Q-FILE-09 | Fail Save Scans after one or more files are written | Export stops at first failure; prior files/partial folder remain; library is unchanged; partial summary/full report use `experimentContext.print`; one modal appears | Automated fault injection plus dialog check |
| Q-FILE-10 | Open and save scans during acquisition and finalization | Actions remain enabled and affect only the independent library; current scan, running item, and pending Queue are unchanged | Automated slow-run probe |
| Q-SHARED-01 | Change path/run/PPT in either GUI | Shared state and both views agree; engine receives empty filename | Automated |
| Q-SHARED-02 | Enter fractional, boundary, empty, and invalid run values | Finite `[0,999]` values round through the shared service; invalid clears | Automated |
| Q-SHARED-03 | Edit Path and Run # during a turbo scan | Current target remains fixed; next scan sees edits; an intervening Run # edit is not overwritten by current-run increment | Automated slow-run probe |
| Q-SHARED-04 | Change PowerPoint state before and after finalization begins | One snapshot at finalization entry governs current scan; later edits apply to future scans | Automated slow-finalization probe |
| Q-SHARED-05 | Recreate either GUI after changing Path, Run #, or PowerPoint state | New handles consume the unchanged canonical state; widget defaults never overwrite or rebase it | Automated |
| Q-RUN-01 | Render/call Start with Queue empty, during active scan, or during inter-item phase | Empty view disables Start; every direct/stale call is an early silent no-op and leaves queue/selection unchanged | Automated |
| Q-RUN-02 | Run scans and raw commands in sequence | Exact order; scans use turbo; raw lines evaluate once on client | Automated |
| Q-RUN-03 | An active item completes normally | Pending callbacks are serviced; the next pending item starts immediately if still allowed, or the phase becomes idle after the queue drains | Automated |
| Q-RUN-04 | A raw command throws | Runner returns idle, failed item stays consumed, later pending remains, full report prints once, and the named modal appears | Automated fault injection plus dialog check |
| Q-RUN-05 | Inspect Start/Run callback dispatch during execution | Executing callback remains interruptible; duplicate action is canceled by state guard | Automated callback probe |
| Q-STOP-01 | Decline then accept the specified Stop Now dialog | Title/message/buttons match; Cancel is default and a no-op; acceptance saves partial result/reason and preserves pending | Automated stop path plus dialog check |
| Q-STOP-02 | Request Stop Queue | Current completes; no later item starts; pending remains | Automated |
| Q-STOP-03 | Escape, confirmed plot close, or safety stop | Same graceful metadata/save behavior; queue halts | Existing stop regressions |
| Q-STOP-04 | Dispatch either stop during the between-item callback transition | No next item starts; all pending items remain | Automated timer callback |
| Q-STOP-05 | Request stops during yielding and non-yielding raw commands | Stop Now stays disabled; Stop Queue latches when dispatchable, is serviced before the next-item decision, and no later item starts | Automated interruptible callback |
| Q-STOP-06 | Request Stop Queue during a scan, then confirm Stop Now before it finishes | Deferred stop escalates to graceful stop now; partial save completes and pending items remain | Automated stop path plus dialog check |
| Q-STOP-07 | Dispatch stops during finalization and between-item transition | Finalizing disables Stop Now; Stop Queue or stale Stop Now halts after current; between-item stop prevents next start without a Stop Now dialog | Automated callback probe |
| Q-ERROR-01 | Propagated scan setup/client/finish/finalization error, with queue view open and closed | Cleanup completes; runner returns idle without rethrow, failed item stays consumed, pending remains, plain full report passes once through `experimentContext.print`, and named modal appears | Automated fault injection plus dialog check |
| Q-ERROR-02 | Slack send fails | Warning is reported and next pending item still starts | Automated mock |
| Q-ERROR-03 | Acquisition or final dirty-flush failure is converted to a graceful stop | Finish actions and partial save complete; stop metadata/notification are preserved; queue halts with later pending items untouched and no extra error modal | Automated fault injection |
| Q-NOTIFY-01 | Complete and gracefully stop scans; run a raw command | Scan notifications include artifacts/duration/state/reason, resolved ID caches, raw sends none | Automated mock |
| Q-REBIND-01 | `smready` during an engine scan, raw command, or between-item transition, then while idle | Every active call throws before mutation; idle rebind preserves queue model/shared state | Automated |
| Q-RACK-01 | Observe Edit Rack across queue and engine lifecycles | Disabled through every non-idle queue phase and startup/acquisition/finish/save; restored afterward | Automated slow-finish/raw/between probe |
| Q-EDIT-09 | Use scan editor and transfer actions during a turbo queue scan | Edit/transfer remain functional without affecting running item; editor Run and Edit Rack remain unavailable | Automated slow-run focus probe |
| Q-VIEW-03 | Keep a native Open/Save dialog open during turbo acquisition | Worker acquisition continues; client updates/final handshake may wait; polling resumes after close and queue state is unchanged | Automated where deterministic plus manual check |
| Q-SAFE-01 | Start a safe-mode scan with the queue view open | Observable engine mode/phase report the lifecycle; all queue controls/menus disable, content dims, and lock message appears | Automated slow-run probe plus visual check |
| Q-SAFE-02 | Close/reopen or call `sm` during safe mode | Close detaches only; one reopened singleton is immediately locked; safe scan and all queue/model state remain unchanged | Automated interruptible callback probe |
| Q-SAFE-03 | Complete or fail a safe-mode scan | Mode/phase clear on every cleanup path; existing view restores current enabled states without focus theft; pending work does not auto-start | Automated success/fault injection plus focus probe |
| Q-VIEW-01 | Refresh existing view from external model change | No focus theft; controls reflect model; no stale-handle error | Automated focus/handle probe |
| Q-VIEW-02 | Close and reopen after changing shared path/run/PPT state | Recreated view reflects unchanged shared state | Automated |
| Q-VIEW-04 | Click the figure background, a control without a panel ancestor, or either source pane | Background/unrelated clicks preserve the active source without errors; source-pane clicks select the matching source | Automated callback target probe |
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

- Default size is 924 x 800 pixels within two pixels per dimension. The resize
  clamp never permits width below 724 pixels or height below 600 pixels. The
  window is resizable in both dimensions.
- At minimum, default, 150-percent width, and 150-percent height, no control may
  overlap, clip outside its parent, acquire negative dimensions, or become
  unusable.
- The compact top strip remains 60--80 pixels high. Save, PowerPoint, and
  Notifications remain within three percentage points of 40, 35, and 25
  percent of its usable width.
- Schedule absorbs all remaining growth. Available Scans and Queue keep equal
  operational width within two pixels; at default size each is approximately 374
  pixels wide. The center insertion lane remains 120--121 pixels wide. Available
  Scans and Raw Commands remain within three percentage points of the 80/20
  vertical split.
- The three insertion actions remain visually distinct, separated enough to
  avoid misclicks with at least 16 pixels between controls, 56 pixels high,
  centered in their lane, and above the vertical midpoint.
- The Queue status remains one line above an execution row ordered `Start`, `Stop
  Queue`, `Stop Now`. All three controls have the same dimensions, `Start` is
  left-aligned, `Stop Queue` is centered, and `Stop Now` is right-aligned. The two
  inter-button gaps are equal within one pixel and at least 15 pixels.
- Running item, pending queue, active insertion source, empty states, and each
  queue phase are visibly distinguishable without relying on color alone.
- Finalization is explicitly labeled `Finalizing: <name>`; it is not presented as
  interruptible acquisition.
- Start is green, Stop Now red, and Stop Queue amber. Disabled and
  stopping-after-current states remain legible.
- Long paths and PowerPoint filenames may be shortened visually, but their full
  value remains available by tooltip and the model value is unchanged. Scan names
  and the Slack account remain on one line with natural clipping, no wrapping or
  manual ellipses, and their complete values available by tooltip.
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

- `code/smbridge/sm.m`: programmatic singleton construction and responsive
  layout.
- `code/smbridge/sm_Callback.m`: scan-library I/O, queue controller, raw-command,
  shared-state, run, notification, stop, and keyboard behavior.
- `code/smbridge/smQueueState.m`: GUI-independent library, pending queue,
  selection, draft, runner, and stop state.
- `code/smbridge/smQueueRefresh.m`, `smQueueBindEngine.m`, and
  `smQueueTransferScan.m`: guarded view rendering, observable engine lifecycle,
  and scan-editor transfer integration.
- `code/smbridge/smgui_small.m`: scan editor plus `TO SCANS`, `TO QUEUE`, and
  direct safe-mode Run behavior.
- `code/smbridge/smready.m`: engine binding and GUI launch lifecycle.
- `code/smbridge/shared/`: shared data-path, PowerPoint, and run-number state.
- `code/sm2/@measurementEngine/`: run-state, turbo execution, stop metadata,
  error cleanup, finish actions, and final saving.
- `docs/SMBRIDGE_GUI_ARCHITECTURE.txt`: current bridge and queue-view
  architecture.
- `tests/test_gui_run_buttons_ignore_active_scan.m` and
  `tests/test_queue_user_cancel_stops_queue.m`: existing queue-facing regression
  coverage; the acceptance matrix above defines the additional required tests.

## Unresolved Decisions

None. Any newly discovered behavior gap must be added here and resolved before
implementation proceeds through that branch.
