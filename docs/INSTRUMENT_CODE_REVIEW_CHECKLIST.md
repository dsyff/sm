# Instrument Code Review Checklist

Use this checklist for new or modified physical instruments, virtual instruments,
setup recipes, and demo scripts.

## Virtual Instruments

- Constructor signature uses `masterRackProxy (1, 1) instrumentRackProxy`, and the
  superclass call is `virtualInstrumentInterface(address, masterRackProxy)`.
- Virtual channel I/O goes through `obj.getMasterRackProxy()` and the rack proxy
  methods: `rackGet`, `rackSetWrite`, `rackSet`, and `rackSetCheck`.
- No virtual instrument calls another instrument's `getChannel`, `setChannel`,
  `setWriteChannel`, `setCheckChannel`, or by-index variants.
- No virtual instrument writes directly to serial/VISA/TCP/SDK communication
  handles. These writes bypass software limits, ramp origin tracking, retries,
  batching, and set-check bookkeeping.
- Any use of `getReviewedInstrumentHandleForNonChannelMethod` is explicitly
  justified, limited to true non-channel methods, and not used for physical
  channel I/O or communication-handle writes.
- Constructors do not accept physical instrument handles or communication handles
  for later physical writes. This cannot be reliably guarded at runtime.
- Virtual instruments do not read or write their own virtual channels through the
  rack, which would create recursion.
- Settable virtual channels keep only the internal state needed to map virtual
  requests to physical targets, and use `rackSetWrite` when set-check is handled
  by the virtual channel.

## Physical Instruments

- The class inherits from `instrumentInterface` and registers all channels in the
  constructor with `addChannel`.
- Helper methods return numeric column vectors with the declared channel size.
- `setWriteChannelHelper` validates instrument-specific expectations, sends one
  clear command path, and leaves set verification to `setCheckChannelHelper`.
- `requireSetCheck=false` is used only when the instrument API cannot verify a set
  or the command is trusted by design.
- `flush` is implemented for buffered I/O instruments, but helpers do not flush
  repeatedly unless the hardware requires it.
- Per-instrument pacing uses `writeCommandInterval`; avoid fixed pauses in rack or
  engine hot paths.
- Instrument SDK/API dependencies are local to the instrument folder where
  practical, not machine-specific absolute paths.
- Instrument output uses `experimentContext.print(...)` in `code/sm2` and
  `code/instruments`.

## Rack, Recipes, and Demos

- All hardware access during measurements goes through rack APIs so software
  limits, ramp state, retries, batching, and verification remain consistent.
- `rack.addChannel` metadata matches the physical channel size, units, tolerances,
  ramp rates, ramp thresholds, and software limits expected by the instrument.
- Recipe `numWorkersRequested` matches each instrument's worker requirement.
- Demo `_Use` flags are reset to `0` before staging.
- Demo instrument sections stay in the same order across address declarations,
  `_Use` flags, and `if ..._Use` blocks.
- Demo files do not contain private email addresses or machine-specific secrets.
