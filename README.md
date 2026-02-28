# sm 1.5 - MATLAB Measurement Automation System

## 🚀 QUICK START:
- Clone or download the latest `sm-dev` or `sm-main` repository to your desktop
- Copy the newest recipe demo (`demos/demo.m` or `demos/demo_nE.m`) and adapt it to your experiment
- `demos/demo_nE.m` is hardware-free (toy + virtual instruments) and is safe to play with on any machine
- For recipe-based local debugging (no engine worker), call `smready(recipe, singleThreaded=true)`
- Explicit-rack debug-only scripts belong in `tests/` (git-ignored), not `demos/`
- For rack-script migration to recipe, see `docs/INSTRUMENT_SETUP_GUIDE.txt` ("RACK SCRIPT -> RECIPE SCRIPT MIGRATION")
- The familiar GUI interface is largely unchanged from the original system
- Use `smget("channel")` and `smset("channel", value)` for quick access
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
- **Slack Notifications**: Scan-complete notifications can be sent to Slack. Set `recipe.slack_notification_account_email` to your Slack account email to send a private DM notification; leave it empty to send to the configured group channel. Notifications are sent only for fully non-interrupted scans launched from the queue GUI.
- **GUI Split**: `smgui_small` edits a single scan; `sm`/`sm_Callback` manage the scans library + queue. Rack menu items in the scan GUI are placeholders.
- **Loading Data**: `smload` returns a `payload` struct with named channel arrays in `.channels` and set axes in `.setchannels`.
- **Data Compatibility**: Same file format as legacy system - existing analysis code works unchanged
- **Virtual Instruments**: Create complex scans (e.g., non-linear ramping) and parameter conversions (e.g., gate voltages to n/E)
	- Base class `virtualInstrumentInterface` lives in `code/sm2`; concrete helpers in `code/instruments` should follow the layout shown in `instrument_demo.m`.
- **Scan Stop (Escape)**: Use the Escape key to stop a scan. Plot updates are blocking, so you can stop immediately if something is wrong.
- **Close Button (X)**: Clicking the close “X” will not close the scan figure immediately; it pauses the scan and asks for confirmation.
- **Avoid Nested rackGet**: The rack rejects new batch gets while hardware channels are active; virtual instruments run after that lock is released, so call the rack only from `virtualGetChannelRead` if you need derived reads
- **Worker-Safe Logging (Required)**: In `code/sm2` and `code/instruments`, always use `experimentContext.print(...)` for terminal/status output. Do not use base MATLAB `fprintf(...)`/`disp(...)` there for status logging; worker-to-client log routing depends on `experimentContext.print(...)`. (Demo/utility scripts can use local printing when worker routing is irrelevant.)

## 📘 CANONICAL GUIDES
- `docs/INSTRUMENT_SETUP_GUIDE.txt` (setup workflow, rack usage)
- `docs/INSTRUMENT_CREATION_GUIDE.txt` (instrument authoring best practices)
- `docs/VIRTUAL_INSTRUMENT_CREATION_GUIDE.txt` (virtual instrument authoring)
- `docs/MEASUREMENT_ENGINE_ARCHITECTURE.md` (engine/recipe/safe/turbo architecture + worker protocol)
- `docs/general_coding_guidelines.md` (repo-wide coding guidelines; includes git guidelines)
- `docs/SMBRIDGE_GUI_ARCHITECTURE.txt` (smbridge GUI structure and scan flow)

## 🔧 TROUBLESHOOTING:
- Check instrument addresses and VISA connections (especially adaptor index for GPIB)
- Verify channel names match exactly (case-sensitive)
- When all else fails, try restarting everything

---

📅 **Last Updated**: 20260212
