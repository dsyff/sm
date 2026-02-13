# Measurement Engine Architecture (SM 1.5 / sm2)

## Overview

`measurementEngine` is the client-side orchestrator that runs scans against an `instrumentRack`.
It supports:

- **Rack mode (single-threaded)**: the rack is constructed on the client and the measurement loop runs on the client.
- **Recipe mode (worker engine)**: the rack is constructed on an engine worker from an `instrumentRackRecipe`, and the measurement loop runs on that worker.
- **Recipe mode (single-threaded debug)**: the recipe is materialized on the client (`singleThreaded=true`) and the measurement loop runs on the client.

The legacy GUIs (`smgui_small`, `sm`) are supported through `smbridge` (`smready` + `smguiBridge`).

## Construction modes

### Rack mode (client rack)

- Create and populate an `instrumentRack` on the client.
- Construct the engine with:

```matlab
engine = measurementEngine.fromRack(rack);
```

### Recipe mode (worker engine)

- Build an `instrumentRackRecipe` (serializable construction steps).
- Construct the engine with:

```matlab
engine = measurementEngine(recipe);
```

For local debugging with the same recipe (no engine worker):

```matlab
engine = measurementEngine(recipe, singleThreaded = true);
```

In recipe mode, the engine:

- creates a process pool sized to \(1 + \sum \texttt{numeWorkersRequested}\)
- starts the engine worker via `parfeval`
- builds the rack on the engine worker
- publishes channel metadata back to the client (friendly names + sizes)

## Scan execution modes (safe vs turbo)

`measurementEngine.run(scan, filename, mode)` supports two update strategies when running on a worker engine:

- **safe**: the worker sends a `safePoint` after each datapoint; the client updates plots for each point and acks each update.
- **turbo**: the worker sends periodic `turboSnapshot` updates at a fixed cadence; the client polls, applies only the latest snapshot to the GUI, and continues until an explicit `runDone`.

In the legacy GUIs:

- Scan GUI "Run" uses **safe** mode.
- Queue GUI "Run" uses **turbo** mode.

### Worker-side scan functions

Each mode has a dedicated static method with a self-contained measurement loop (no shared callbacks or function-handle indirection):

- `runTurboScanCore_(rack, scanObj, clientToEngine, engineToClient, requestId, snapshotInterval, logFcn)` — turbo loop.
- `runSafeScanCore_(rack, scanObj, clientToEngine, engineToClient, requestId, logFcn)` — safe loop.

Both functions precompute all per-loop metadata (channels, wait times, data dimensions, strides, plot layout) before the main loop to keep the hot path fast.

A third function, `runScanCore_`, handles **single-threaded** (rack mode) scans. It uses the live figure handle for stop detection instead of a PDQ.

## instrumentRack hot-path notes (2026-02)

Recent rack-side changes that affect scan/runtime behavior:

- Channel friendly-name lookup now uses a `dictionary` cache (instead of repeated linear `find(...)` scans).
- `rackGet` now caches a compiled plan keyed by the ordered channel list:
  - pre-resolved instrument handles
  - pre-resolved instrument-local channel indices
  - precomputed physical batch groups (one channel per instrument per batch)
  - virtual-channel positions
- `instrumentRack.channelTable` now stores instrument-local `channelIndices` so repeated get/set paths avoid channel-name resolution.
- Read-delay ordering is precomputed and cached at channel-registration time (no per-call re-sort for hot paths).
- Set/ramp helpers operate on row-index vectors + cell arrays instead of table copy/filter loops.
- The fixed ramp-loop `pause(0.75)` was removed. Write pacing is now an instrument-level concern via `instrumentInterface.writeCommandInterval`.

### Stop signal (worker modes)

The client sends a stop signal by placing `struct("type", "stop", "requestId", runId)` on the existing `clientToEngine` PDQ. The worker scan functions check for it at multiple points in the measurement loop:

1. Check `clientToEngine.QueueLength > 0` (cheap, no blocking).
2. If > 0, `poll` the message.
3. Verify `type == "stop"` before stopping. Non-stop messages are discarded.

Interruptible waits (`startwait`, `waittime`) use the same inline pattern: poll the PDQ between short `pause` steps.

### Stop signal (single-threaded)

In rack mode, `runScanCore_` receives the live figure handle. At each check point it reads `get(figHandle, "CurrentCharacter")` for ESC and checks `figHandle.UserData.stopRequested` (set by the close-request callback).

### Safe mode protocol

For each data point read:

1. Worker sends `safePoint` to `engineToClient`: `struct("type", "safePoint", "requestId", ..., "loopIdx", ..., "count", ..., "plotValues", ...)`.
   - `plotValues` is a column vector (length = number of display channels).
2. Worker waits for a response on `clientToEngine`:
   - Records `QueueLength`, polls that many messages, handles each one at a time.
   - `"ack"` — proceed to the next point.
   - `"stop"` — set stopped flag and break.
3. Client receives `safePoint`, updates plots with `drawnow`, then sends either `ack` (continue) or `stop` (first time user requests stop).

### Turbo mode protocol

1. Worker maintains a cell array of plot-data arrays (`plotData`), pre-allocated with NaN.
   - 1D displays: `nan(1, npoints(xLoop))`.
   - 2D displays: `nan(npoints(yLoop), npoints(xLoop))`.
   - Arrays are reset to NaN when the outer (3rd+) loop index changes. For a 2-loop scan this happens only once at startup.
2. As each data point is read, the worker fills `plotData` via direct indexing (`plotData{k}(count(yL), count(xL)) = value`).
3. Periodically (default 0.2 s, controlled by the `turboSnapshotInterval` property), the worker sends the complete `plotData` to `engineToClient`: `struct("type", "turboSnapshot", "requestId", ..., "count", ..., "plotData", {plotData})`.
4. A final snapshot is sent after the loop exits.
5. Client polls `engineToClient`, keeps only the latest `turboSnapshot`, and applies it to the GUI with `drawnow limitrate`.
6. Client continues polling until it receives `runDone`.

### Temp saves

Both scan functions periodically send `struct("type", "tempData", "requestId", ..., "count", ..., "data", {data})` to the client based on `scanObj.saveloop` settings. The client writes this to a single temp file (`filename + "~"`).

## Core data structures

### `measurementScan`

`measurementScan` is a self-contained, serializable scan description. It records:

- constants (`consts`)
- loop definitions (`loops`, including `startwait`/`waittime` as `duration`)
- save-loop metadata (`saveloop`)
- plot selections (`disp`)
- mode flag (`"safe"`/`"turbo"`)
- timing fields (`startTime`, `endTime`, `duration`) filled by `measurementEngine`

Legacy scan structs are converted via `measurementScan.fromLegacy(...)`.

### `instrumentRackRecipe`

`instrumentRackRecipe` is a serializable "build plan" for constructing a rack on a worker:

- `addInstrument(...)` / `addVirtualInstrument(...)`
- `addChannel(...)`
- `addStatement(...)` for additional worker-side code
  - Statements are evaluated sequentially in insertion order during rack build.
  - Prefer one executable line per `addStatement(...)` call so individual setup lines are easy to comment out in demos/scripts.

#### Worker pool sizing (recipe mode)

Recipe mode cannot inspect instrument objects on the client, so **pool sizing is explicit**:

- Pass `numeWorkersRequested = N` (reserved name-value) to `addInstrument(...)` / `addVirtualInstrument(...)`.
- Default is `0`.

Example:

```matlab
recipe.addInstrument("h", "instrument_myInst", "myInst", ..., numeWorkersRequested = 2);
```

## Worker communication

All inter-process links use `parallel.pool.PollableDataQueue` (PDQ) and explicit polling loops:

- **Polling rule**: check `QueueLength > 0` before calling `poll(...)`.
- No `Destination` option.
- Avoid listener-based `afterEach` for latency stability.

### PDQ channels

Two PDQ channels connect the client and engine worker:

| Channel | Direction | Creator | Messages |
|---------|-----------|---------|----------|
| `engineToClient` | worker → client | client (passed to `parfeval`) | `engineReady`, `rackReady`, `safePoint`, `turboSnapshot`, `tempData`, `runDone`, `evalDone`, `rackGetDone`, `rackSetDone`, `rackDispDone`, `parfeval` |
| `clientToEngine` | client → worker | worker (sent back via `engineReady`) | `run`, `stop`, `ack`, `shutdown`, `eval`, `rackGet`, `rackSet`, `rackDisp`, `parfevalDone` |

### Message flow during a scan

```
Client                          clientToEngine PDQ              Worker
  |                                   |                           |
  |--- struct("type","run",...) ------>|                           |
  |                                   |-----> poll, start scan -->|
  |                                   |                           |
  |     (safe mode)                   |                           |
  |<--- safePoint --------------------|<----- send --------------|
  |--- ack or stop ------------------>|                           |
  |                                   |-----> poll, handle ----->|
  |                                   |                           |
  |     (turbo mode)                  |                           |
  |<--- turboSnapshot (periodic) -----|<----- send --------------|
  |--- stop (if ESC pressed) -------->|                           |
  |                                   |-----> poll, verify ----->|
  |                                   |                           |
  |<--- runDone ----------------------|<----- send --------------|
```

## Client vs worker execution helpers

- **Client eval (Queue GUI statements)**: Queue statements are evaluated on the client via `evalin("base", ...)` (not via `smeval`).
- **Worker eval (optional output)**: `smeval(codeString)` calls `measurementEngine.evalOnEngine(...)` in recipe mode and can return a single output when called with an output argument.

## Instrument workers (generic spawning)

Workers cannot spawn workers. If an instrument needs additional background worker(s) (monitor loops, streaming acquisition, etc.), worker-side code must request the client to start them.

### Generic spawn API

In recipe mode, the engine worker installs a function handle in the worker base workspace:

- `sm_spawnOnClient` (engine internal)

Worker-side code should call:

- `requestWorkerSpawn(...)` (public helper)

Example (from engine worker code):

```matlab
requestWorkerSpawn("myInst", @myWorkerMain, 0, arg1, arg2);
```

If the request is **queued** (pool too small), the engine throws a clear error instructing you to increase `numeWorkersRequested` and restart the engine.

## Data saving

At the end of a run:

- The final MAT file contains `scan` and `data`.
- The scan timing fields (start/end/duration) are saved and included in PPT header text (when PPT is enabled).
- The scan object is also saved to a separate `*_scan.mat`.
- A single temp file (`filename + "~"`) is used for intermediate saves.

## Where to look in code

- `code/sm2/measurementEngine.m`: orchestration, worker protocol, scan core functions (`runTurboScanCore_`, `runSafeScanCore_`, `runScanCore_`), client loops, saving/PPT.
- `code/sm2/measurementScan.m`: scan abstraction + legacy conversion.
- `code/sm2/instrumentRackRecipe.m`: worker rack construction recipe.
- `code/sm2/requestWorkerSpawn.m`: generic worker→client spawn helper.
- `code/smbridge/*`: legacy GUI integration layer.
