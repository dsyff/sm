# sm 1.5 - MATLAB Measurement Automation System

## 🚀 QUICK START:
- Clone or download the latest `sm-dev` or `sm-main` repository to your desktop
- Copy the newest recipe demo (`demos/demo.m` or `demos/demo_nE.m`) and adapt it to your experiment
- `demos/demo_nE.m` is hardware-free (toy + virtual instruments) and is safe to play with on any machine
- For recipe-based local debugging (no engine worker), call `smready(recipe, singleThreaded=true)`
- Explicit-rack debug-only scripts belong in `tests/` (git-ignored), not `demos/`
- For rack-script migration to recipe, see `docs/INSTRUMENT_SETUP_GUIDE.txt` ("RACK SCRIPT -> RECIPE SCRIPT MIGRATION")
- Use `smgui_small` to edit and run one scan; use `sm` for the scans library and turbo queue
- Use `smget("channel")` and `smset("channel", value)` for quick channel access
- Use `smget("instrument", "property")` and `smset("instrument", "property", value)` for screened public-property access on the engine rack
- Use `smplot('filename.mat')` to recreate plots
- Use `smload('filename.mat')` to load saved data into a struct for analysis:
	- `payload.scan`: original scan struct
	- `payload.channels`: struct mapping get-channel names → numeric arrays (fieldnames are sanitized via `matlab.lang.makeValidName`)
	- `payload.setchannels`: struct mapping set-channel names (with `_set` appended) → axis vectors
	- `payload.metadata`: filename/comments/consts
	- Optionally: `payload = smload(___, 'includeRaw', true)` adds `payload.raw`

## 🔑 KEY CONCEPTS:
- **Batch Optimization (Pipeline Design)**: A major source of scan speed is coordinated design across `measurementEngine`, `instrumentRack`, and instrument classes. The engine precomputes scan metadata, `instrumentRack` caches/compiles channel plans and batches physical access by instrument, and instrument classes split `getWriteChannelHelper`/`getReadChannelHelper` so query writes are dispatched first and reads are collected after parallel settle time. Most users can rely on normal scan definitions without manual batching logic.
- **Vector Channels**: Rack batching can issue at most one physical channel per instrument in each batch step, so multiple scalar channels from the same instrument still require multiple instrument transactions. When an instrument supports vector reads (e.g., `XY`, `XTheta`, `YTheta`, `RTheta`), one request returns multiple values, which can cut communication overhead by large factors. Vector channels are get-only (no vector setting), and they are plotted/saved as scalar channels with `_#` appended (e.g., `XY_1`, `XY_2`).
- **Worker Engine (safe/turbo)**: Turbo mode uses a multi-process pipeline (client GUI + worker engine process) and asynchronous snapshot updates to achieve extremely fast scan speed. When constructed from an `instrumentRackRecipe`, measurements run on a worker engine by default; use `singleThreaded=true` to materialize the recipe on the client for local debugging. The scan GUI "Run" uses safe mode, while the queue GUI "Run" uses turbo mode.
- **Class-First Design**: The new codebase uses classes extensively for cleaner structure. Instrument classes inherit `instrumentInterface`, so most plumbing is already handled; simple instruments should require minimal code (typically just constructor/channel definitions plus small get/set helper methods).
- **Slack Notifications**: Completed and stop-requested queue scans can send their saved image/data and status to Slack; stop notifications include the stop reason. Set `recipe.slack_notification_account_email` to your Slack account email to send a private DM notification; leave it empty to send to the configured group channel. Slack connection/API failures are non-fatal and are reported through `experimentContext`.
- **Finish Actions ("Set After")**: The scan GUI's **When finished or canceled** panel uses checked rows to set scalar channels and unchecked rows to record their final values. All sets run before the reads, and the actions run before final saving after normal completion, cancellation, or a handled acquisition error. Refreshed rows are saved in `scan.finish` and included in MAT/PPT output.
- **Protected Gates**: Enable `virtual_gate_bg_Use` or `virtual_gate_tg_Use` in `demos/demo.m`, then use the protected `V_bg`/`V_tg` and `I_bg`/`VI_bg` channels rather than their `_raw` counterparts. After `occurrence` out-of-range current reads (default 3, minimum 2) at strictly increasing absolute protected SET voltages, the gate is zeroed immediately without a ramp and the active scan stops gracefully, preserving its reason and partial final data. Change live limits with `smset("virtual_gate_bg", "currentMin", ...)`, `currentMax`, or `occurrence`.
- **GUI Updates**: `smgui_small` now has scrollable Constants, loop, and finish-action sections, and numeric range edits update in place so the active textbox keeps focus. **File > Edit Rack** can apply ramp-rate, ramp-threshold, and software-limit changes while no scan is active. The current `sm` queue GUI still manages `smaux.scans`/`smaux.smq`; its programmatic singleton replacement is specified in `docs/QUEUE_GUI_DESIGN.md` but is not implemented yet. Repeated Run clicks during an active scan are ignored.
- **Loading Data**: `smload` returns a `payload` struct with named channel arrays in `.channels` and set axes in `.setchannels`.
- **Data Compatibility**: Same file format as legacy system - existing analysis code works unchanged
- **Virtual Instruments**: Create complex scans (e.g., non-linear ramping) and parameter conversions (e.g., gate voltages to n/E)
	- Base class `virtualInstrumentInterface` lives in `code/sm2`; concrete helpers in `code/instruments` should follow the layout shown in `instrument_demo.m`.
- **Scan Stop**: Escape, a confirmed plot-window close, and instrument-requested safety stops follow the same graceful-stop path: finish actions and final saving still run, the stop reason is recorded, and a queue leaves its remaining entries pending.
- **Close Button (X)**: Clicking the plot-window close “X” during a scan asks for confirmation before stopping and closing it.
- **Avoid Nested `rackGet`**: The rack rejects nested batch gets while physical channels are active. Virtual channels run after that lock is released, so derived reads belong in a virtual instrument's `getReadChannelHelper` and must use its `instrumentRackProxy`.
- **Worker-Safe Logging (Required)**: In `code/sm2` and `code/instruments`, always use `experimentContext.print(...)` for terminal/status output. Do not use base MATLAB `fprintf(...)`/`disp(...)` there for status logging; worker-to-client log routing depends on `experimentContext.print(...)`. (Demo/utility scripts can use local printing when worker routing is irrelevant.)

## 🔔 SLACK API SETUP

Create `secrets.env` in the repository root, next to `README.md`. The file is already git-ignored; never commit Slack tokens or copy them into a demo/recipe.

For the normal private-DM workflow, the only required secret is the Slack API token:

```dotenv
slack_notification_api_token=xoxb-your-bot-token
```

Set the recipient in the copied recipe:

```matlab
recipe.slack_notification_account_email = "you@example.com";
```

- To send to the configured group channel instead, leave `recipe.slack_notification_account_email` empty and add `slack_notification_channel_id=C0123456789` to `secrets.env`.
- `slack_notification_account_email` is also accepted in `secrets.env`, but normally omit it so each copied recipe controls its DM recipient. If set there, it takes precedence over the recipe value and over the channel ID.
- Run or rerun `sminit` after creating or changing `secrets.env`, then call `smready(...)` so the loaded settings reach the measurement engine.
- `slack_notification_webhook` is still loaded for compatibility, but webhook-only setup is not sufficient for the current image/data upload path.

## 📘 CANONICAL GUIDES
- `docs/INSTRUMENT_SETUP_GUIDE.txt` (setup workflow, rack usage)
- `docs/INSTRUMENT_CREATION_GUIDE.txt` (instrument authoring best practices)
- `docs/SDG2042X_WAVEFORM_GENERATORS.md` (DDS, TrueARB, multi-tone, pure-tone, and CASCADE behavior)
- `docs/VIRTUAL_INSTRUMENT_CREATION_GUIDE.txt` (virtual instrument authoring)
- `docs/MEASUREMENT_ENGINE_ARCHITECTURE.md` (engine/recipe/safe/turbo architecture + worker protocol)
- `docs/general_coding_guidelines.md` (repo-wide coding guidelines; includes git guidelines)
- `docs/SMBRIDGE_GUI_ARCHITECTURE.txt` (smbridge GUI structure and scan flow)
- `docs/QUEUE_GUI_DESIGN.md` (current design for the not-yet-implemented programmatic queue GUI)
- `docs/ATTODRY_AUTOFOCUS_AUTOSHIFT_DESIGN.md` (XY autoshift control design, stepper physics, tolerance rationale)

## 🔧 TROUBLESHOOTING:
- Check instrument addresses and VISA connections (especially adaptor index for GPIB)
- Verify channel names match exactly (case-sensitive)
- When all else fails, try restarting everything

---

📅 **Last Updated**: 20260812
