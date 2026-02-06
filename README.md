# sm 1.5 - MATLAB Measurement Automation System

## 🚀 QUICK START:
- Clone or download the latest `sm-dev` or `sm-main` repository to your desktop
- Copy the newest `demos/demo.m` and adapt it to your experiment
- The familiar GUI interface is largely unchanged from the original system
- Use `smget("channel")` and `smset("channel", value)` for quick access
- Use `smplot('filename.mat')` to recreate plots
- Use `smload('filename.mat')` to load `smrun_new` save data into a struct for analysis:
	- `payload.scan`: original scan struct
	- `payload.channels`: struct mapping get-channel names → numeric arrays (fieldnames are sanitized via `matlab.lang.makeValidName`)
	- `payload.setchannels`: struct mapping set-channel names (with `_set` appended) → axis vectors
	- `payload.metadata`: filename/comments/consts
	- Optionally: `payload = smload(___, 'includeRaw', true)` adds `payload.raw`

## 🔑 KEY CONCEPTS:
- **Batch Optimization**: getWrite/getRead separation and smart ordering for performance
	- Prefer batched rack calls when possible: `rackGet(["ch1","ch2"])` and `rackSetWrite(["ch1","ch2"], [v1; v2])`
- **Vector Channels**: Multi-element channels that save instrument read time (e.g., XY, XTheta, YTheta, RTheta) supported in smgui and instruments (get only, no vector setting). Vector channels are plotted and saved as scalar channels with `_#` appended (e.g., `XY_1` is X and `XY_2` is Y).
- **GUI Split**: `smgui_small_new` edits a single scan; `sm`/`sm_new_Callback` manage the scans library + queue. Rack menu items in the scan GUI are placeholders.
- **Loading Data**: `smload` returns a `payload` struct with named channel arrays in `.channels` and set axes in `.setchannels`.
- **Data Compatibility**: Same file format as legacy system - existing analysis code works unchanged
- **Virtual Instruments**: Create complex scans (e.g., non-linear ramping) and parameter conversions (e.g., gate voltages to n/E)
	- Base class `virtualInstrumentInterface` lives in `code/sm2`; concrete helpers in `code/instruments` should follow the layout shown in `instrument_demo.m`.
- **Scan Stop (Escape)**: Use the Escape key to stop a scan. Plot updates are blocking, so you can stop immediately if something is wrong.
- **Close Button (X)**: Clicking the close “X” will not close the scan figure immediately; it pauses the scan and asks for confirmation.
- **Avoid Nested rackGet**: The rack rejects new batch gets while hardware channels are active; virtual instruments run after that lock is released, so call the rack only from `virtualGetChannelRead` if you need derived reads

## 📘 CANONICAL GUIDES
- `docs/INSTRUMENT_SETUP_GUIDE.txt` (setup workflow, rack usage)
- `docs/INSTRUMENT_CREATION_GUIDE.txt` (instrument authoring best practices)
- `docs/VIRTUAL_INSTRUMENT_CREATION_GUIDE.txt` (virtual instrument authoring)
- `docs/general_coding_guidelines.md` (repo-wide coding guidelines)
- `docs/SMBRIDGE_GUI_ARCHITECTURE.txt` (smbridge GUI structure and scan flow)

## 🔧 TROUBLESHOOTING:
- Check instrument addresses and VISA connections (especially adaptor index for GPIB)
- Verify channel names match exactly (case-sensitive)
- Check `filename-tempN.mat~` files if scan crashed
- When all else fails, try restarting everything

---

📅 **Last Updated**: 20260115
