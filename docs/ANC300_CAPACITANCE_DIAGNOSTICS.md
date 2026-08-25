# ANC300 Stick-Slip Positioner Capacitance Diagnostics

Last reviewed 2026-08-13.

## Conclusion

The attocube ANC300 controller and its ANM150, ANM200, and ANM300 axis
modules can measure the capacitance of an attached piezo positioner. The
measurement is available from the controller GUI and from the standard remote
console.

`sm-dev` does **not** currently expose that capacitance. The production
[`instrument_ANC300`](../code/instruments/instrument_ANC300.m) class exposes
only X/Y/Z stepping voltage and frequency, plus explicit step methods. The
canonical [`demo.m`](../demos/demo.m) consequently adds only `Vx`, `Vy`, `Vz`,
`fx`, `fy`, and `fz`.

Capacitance is a useful electrical diagnostic, but it is not a position,
displacement, step-size, motion, or mechanical-health measurement. A plausible
capacitance makes the piezo and its electrical path look broadly plausible; it
does not prove that the stage is mounted correctly, free to move, or producing
steps.

## Terminology and the Current Setup

| Term | Meaning here |
| --- | --- |
| ANC300 | The modular open-loop controller/electronics. |
| ANM150/200/300 | Axis-module types installed in an ANC300. All three documented module types provide capacitance measurement. |
| ANPx101/LT | The X/Y linear stick-slip positioners named in the autofocus configuration. |
| ANPz102/LT | The Z stick-slip positioner named in the autofocus configuration. |
| Commanded step | One `stepu` or `stepd` count. The autofocus design also calls this a “microstep”; that is local software terminology, not capacitance readout. |

The current driver hard-codes X, Y, and Z to ANC300 axis IDs 3, 4, and 5. It
puts those axes in `stp` mode at construction and limits the configured
stepping amplitude to 0–60 V. The ANC300 manual discusses broader controller
capabilities up to 150 V; those values do not override the limits selected for
this setup.

The local 2024 system offer identifies two ANPx101/LT stages, one ANPz102/LT
stage, one ANC300, three ANM150 stepping modules, an ANSxy100lr/LT scanner, and
two ANM200 scanner modules. The quantities strongly support pairing the three
stick-slip stages with the three ANM150 modules, but the offer does not map
module slots to driver axis IDs. Confirm the installed module identity for
axes 3–5 on the live controller before relying on that pairing.

## What the ANC300 Measures

The ANC300 manual describes the active measurement as follows:

1. The axis module applies approximately 100 mV to charge the attached piezo.
2. It measures the discharge time.
3. It calculates and stores a capacitance value.
4. The result is displayed in the GUI or can be read remotely.

The manual treats capacitance as an indicator of:

- electrical continuity/function of the connected piezo system;
- a possible open connection or short circuit when the value is not as
  expected; and
- piezo temperature, because piezo capacitance is temperature dependent.

This is a coarse diagnostic. The manual cautions that an ANC300 result may
differ by about 10–20% from the specified value, especially at room
temperature, and may differ from values obtained with another measurement
technique. Use a positioner specification or a known-good per-axis baseline;
do not invent a universal pass/fail threshold.

The controller measures the electrical load seen at its output. The manual
calls this the capacitance of the connected piezo, but cabling and connectors
are part of the measured electrical path in practice. That last sentence is an
engineering interpretation, not a separately quantified manual specification.

## Remote Console Interface

For a fresh measurement on axis `<AID>`, the ANC300 v3.4 manual documents:

```text
setm <AID> cap    # start a capacitance measurement
capw <AID>        # wait for the measurement to finish
getc <AID>        # read the saved capacitance value
```

For this repository, `<AID>` is 3 for X, 4 for Y, or 5 for Z.

Important state semantics:

- `setm <AID> cap` starts the active measurement. The axis need not first be
  placed in `gnd`; entering `cap` mode disables incompatible functions.
- After measurement, the controller returns the axis to `gnd` mode.
- `capw <AID>` waits for completion.
- `getc <AID>` only returns the saved value. It does not initiate a new
  measurement, so the returned value can be stale.
- The console uses CR/LF-terminated ASCII and returns optional data lines
  followed by `OK`, or `ERROR` on failure.

The current `stepAxis`/`stepXY` implementation assumes that an axis is already
in `stp` mode. A fresh capacitance measurement therefore makes later stepping
fail until the axis is explicitly returned to `stp` mode. This side effect is
why an active measurement must not be hidden inside an ordinary scan GET.

### Unit boundary

The manual's power-limit table labels capacitance in microfarads (`µF`), but
the standard-console section does not show an example `getc` response or
explicitly define its returned token and unit. No local command log contains a
captured `getc` response. A future implementation must first capture and
document the real raw response; until then it must not assume `µF` or reuse the
AMC API's `nF` unit.

## Safety and Operational Meaning

### The measurement can move the stage

Approximately 100 mV is applied during an active measurement. The ANC300
manual warns that this can produce small mechanical motion and damage a
sensitive structure or experiment. Only run it when every affected
positioner/sample is in a safe state. A cached `getc` read does not start this
active measurement.

### The value participates in controller protection

The ANC300's output-power limit depends on capacitance because drive power
scales with the capacitive load. The manual instructs the operator to measure
capacitance before applying output voltage and to remeasure after:

- changing a positioner or the setup; or
- a large temperature change.

If no capacitance has been measured, the controller applies its most
restrictive output limit. If an old value remains after a setup or temperature
change, the calculated power limit may be inappropriate and the controller can
overheat.

### What a result can and cannot tell us

| Observation | Supported interpretation | Not established |
| --- | --- | --- |
| Stable value near a positioner specification or known-good baseline | Piezo/electrical path is broadly plausible at that temperature. | Actual position, successful motion, step size, direction, friction, or mounting quality. |
| Unexpected or absent value | Investigate a disconnected/open path, short, damaged piezo, cabling, connector, wrong axis, stale value, or temperature change. | The capacitance result alone does not uniquely identify which failure occurred. |
| Value changes with temperature | Expected in principle for a piezoelectric actuator. | A universal capacitance-to-temperature calibration. |

The FlexPositioners manual adds useful non-capacitance checks for a positioner
that does not move: rigid mounting, unobstructed travel, appropriate voltage
and frequency, low-resistance cabling (less than 5 Ω in that manual), connector
integrity, and isolation by swapping the positioner/cable/controller axis. Any
resistance or continuity work must follow the manual's power-down and high-
voltage safety instructions.

## Current `sm-dev` Exposure

| Surface | Current behavior |
| --- | --- |
| `instrument_ANC300` channels | `voltage_x`, `voltage_y`, `voltage_z`, `frequency_x`, `frequency_y`, `frequency_z` only. |
| `instrument_ANC300` public methods | `stepAxis` and `stepXY`; no capacitance method. |
| Driver protocol commands | `ver`, `setm ... stp`, `setf/getf`, `setv/getv`, `stepu/stepd`, and `stepw`; no `cap`, `capw`, or `getc`. |
| `demos/demo.m` rack aliases | `Vx`, `Vy`, `Vz`, `fx`, `fy`, and `fz`; no capacitance channel. |
| Autofocus virtual instrument | Uses ANC300 voltage channels and reviewed access to `stepAxis`; it does not read capacitance. |

Thus the hardware/controller capability exists, but it is not yet part of the
production MATLAB interface.

## Recommended Software Boundary

If this is implemented later, keep the passive cached value separate from the
active diagnostic:

1. An explicit physical-driver method such as
   `measureCapacitanceDiagnostic(axis)` should perform `setm ... cap`, `capw`,
   and `getc`. Its documentation and return value should make the active
   voltage and grounded postcondition explicit.
2. A separate method such as `readStoredCapacitance(axis)` may issue only
   `getc`, clearly identifying the result as cached and possibly stale.
3. Optional read-only rack channels may expose the stored value for logging
   only after the exact response format and unit are verified. Their names
   should say that the value is stored/cached and include the confirmed unit.
4. Do not make an ordinary channel GET trigger a fresh measurement. It would
   apply a voltage, disrupt batching, change controller mode, and leave the
   axis unable to step.
5. Throw a specific error on an unsupported axis module, malformed response,
   unknown unit, timeout, or failed measurement. Do not guess a value or unit.

The explicit active method should leave the axis grounded unless its contract
deliberately says otherwise. Returning to `stp` should be a separate,
intentional operation so a diagnostic cannot silently re-enable the drive
state.

## Do Not Confuse ANC300 and AMC Diagnostics

A separate local vendor MATLAB package,
`temp/atto-device-matlab-1.12.0/atto_device/AMC`, targets the newer AMC100,
AMC150, and AMC300 JSON-RPC API. Its `diagnostic_startDiagnostic` call starts a
per-axis diagnostic, while `diagnostic_getDiagnosticResults` returns both
`capacity` in nF and resistance in Ω for axes 0–2.

That AMC API is not the interface used here. The production class verifies an
**ANC300** and communicates using its serial text console with axis IDs 3–5.
AMC wrapper functions must not be copied into the ANC300 driver or used as
evidence for the ANC300 console unit.

## Live Validation Needed Before Implementation

No active capacitance measurement was run during this documentation audit.
Before adding production code:

1. Put the sample and all three positioners in a state where possible motion
   from the diagnostic is safe, and stop scans/autofocus compensation.
2. Record `ver`, the relevant axis/module identities, and `getm 3`, `getm 4`,
   and `getm 5`.
3. On one safe axis, capture the complete raw responses and timing for
   `setm <AID> cap`, `capw <AID>`, `getc <AID>`, and the final `getm <AID>`.
4. Confirm the numeric format, unit, invalid/no-measurement representation,
   timeout behavior, and grounded postcondition.
5. Repeat enough times to establish measurement scatter, then establish
   per-axis baselines at the temperatures relevant to the experiment.
6. Confirm the intentional transition back to `stp` before allowing another
   step command.

## Sources and Evidence Boundary

Manual-backed claims above were checked against these local manufacturer
manuals, including rendered inspection of the cited pages:

- `C:\Users\Thomas\Desktop\manuals\attocube ANC300 positioner controller.pdf`
  — *ANC300 User Manual: Piezo Positioning Electronic*, version 3.4, June
  2019. See pp. 29, 35–41, and 46–48. The exact PDF was formerly
  tracked as `manuals/Attocube ANC300 positioner controller.pdf`; it remains in
  repository history as Git blob `94b589612b51e8e828f67c61e8896cd3e6bd6506`.
- `C:\Users\Thomas\Desktop\manuals\Attodry\05 Manual FlexPositioners &
  Scanner_v2.9.pdf` — *AN* series positioners & scanners User Manual*, version
  2.9, January 2023. See pp. 29–30.
- `C:\Users\Thomas\Desktop\sm-dev\temp\133912_5_BC_Ma.pdf` — local offer
  133912-5, dated March 21, 2024. PDF p. 5 (printed offer p. 4) lists the
  positioners, controller, and module quantities summarized above. An offer
  records the specified system, not a live inventory.

The current software-exposure findings come from
[`instrument_ANC300.m`](../code/instruments/instrument_ANC300.m),
[`demo.m`](../demos/demo.m), and
[`virtualInstrument_attodryAutofocus.m`](../code/instruments/@virtualInstrument_attodryAutofocus/virtualInstrument_attodryAutofocus.m).
The AMC comparison comes from the locally present, git-ignored vendor MATLAB
package named above. Anything listed under “Live Validation Needed” remains
unverified on the connected controller.
