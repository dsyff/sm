# SM Project Context and Guardrails

This document captures the recurring expectations for development in the `sm` repository so they do not need to be restated in future tasks.

## 📌 Platform & Environment
- Target environment is **MATLAB on 64-bit Windows**.
- Instruments are implemented as subclasses of `instrumentInterface` under `code/instruments`.
- Demo scripts live in `demos/` and simple validation scripts live in `tests/`.
- Default branch workflow: feature work happens on `dev`; `main` only receives fast-forward merges from `dev`.

## 🧭 Coding Guidelines
- Keep implementations **concise**—avoid redundant fallbacks, superfluous assertions, or blunt `warning` spam.
- Prefer MATLAB channel-based interactions (`addChannel`, `setChannel`, `getChannel`) over ad-hoc helper methods.
- When overriding `setWriteChannelHelper`, validate inputs explicitly and surface descriptive error IDs/messages.
- Always clean up hardware resources in `delete`/`shutdown` blocks and ignore benign shutdown failures.
- Favor immutable constants (`properties (Constant, Access = private)`) for driver magic numbers.
- `flush` should be a no-op unless the instrument buffers outbound commands.

## 🔌 Instrument Integration Expectations
- All instruments must operate **without external fallbacks**; only the intentional code path should run.
- Channel numbering convention:
  1. Primary write/read index (e.g., `pixel_index`).
  2. Primary measurement channel (e.g., `counts`).
  3. Additional configuration (e.g., `exposure_time`).
- Channel setters should not coerce invalid values—reject non-integer indices, negative exposures, etc.
- When a channel change invalidates cached data, clear caches immediately so the next read forces a refresh.

## 🧪 Testing & Demos
- Provide a lightweight MATLAB script mirroring `demos/demo.m` whenever a new instrument is added.
- Tests/scripts should instantiate the instrument, touch a couple of channels, optionally slot into a temporary `instrumentRack`, and perform cleanup with `onCleanup` guards.
- Avoid direct DLL poking in tests; rely on the instrument constructor instead.

## 🎯 Andor SDK2 Requirements Snapshot
*(See `docs/context_andor_sdk2_requirements.md` for future deep dives.)*
- Use the 64-bit .NET assembly: load `ATMCD64CS.dll` from `matlabroot` via `NET.addAssembly(fullfile(matlabroot, "ATMCD64CS.dll"))`.
- Do **not** attempt 32-bit support or alternate DLL fallbacks.
- No `Initialize` directory is required—call `Initialize("")`.
- Apply full vertical binning (`SetReadMode(READ_MODE_FVB)`) immediately after initialization.
- Default acquisition configuration:
  - `ACQ_MODE_SINGLE_SCAN`
  - Internal trigger (`SetTriggerMode(DEFAULT_TRIGGER_MODE)`)
  - Default exposure = `0.1` s, exposed as channel `"exposure_time"`
- `pixel_index` must be an integer within the detector range (no rounding).
- `exposure_time` channel must update the camera through `SetExposureTime` and invalidate cached spectra.
- Spectrum acquisition path: `StartAcquisition` → `WaitForAcquisition` → `GetAcquiredData` into a `System.Int32` array → convert to `double` → mark cache fresh.

Keeping these expectations in mind should make future feature requests faster and avoid repeated clarification.
