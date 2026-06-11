# Attodry Autofocus And XY Autoshift Design Notes

This document records hardware behavior and the control design constraints for
`virtualInstrument_attodryAutofocus`. It is not an implementation log for
git-ignored smoke-test scripts. Those scripts are local diagnostics used to
validate a design before porting it into the production instrument.

Code map:
- Production instrument:
  `code/instruments/@virtualInstrument_attodryAutofocus/virtualInstrument_attodryAutofocus.m`
- Local diagnostics, ignored by git:
  `tests/autofocus testing/`

Last updated 20260611.

## Hardware Behavior

- The ANC300 stick-slip axes have a two-segment voltage response. Below a
  turn-on voltage, commanded steps produce little or no motion. Above turn-on,
  the mean image displacement per microstep is approximately linear in voltage:
  `px_per_step = slope * V + intercept`.
- Near turn-on, percentage scatter is large. A voltage that is useful for
  detecting motion may still be too noisy for accurate correction.
- Positive and negative directions can be asymmetric. Calibration should first
  probe both directions at the same voltage so that nonzero net drift is
  measured rather than assumed away. Separate + and - operating voltages are
  justified only after the data show reproducible directional clustering.
- The camera axes need not align with positioner X/Y. The live response matrix
  must be measured from images; persisted calibration data should store scalar
  voltage-response information, not sample-specific direction vectors.
- XY and Z are weakly coupled. XY stepping can defocus the sample, and Z
  stepping can shift the image in XY. The expected convergence path is still
  simple because the coupling is small, but calibration cannot assume it is
  zero.
- Temperature changes alter the step response. T/B compensation should keep
  recalibrating from recent local behavior instead of relying indefinitely on a
  stale voltage profile.

## Image And Reference Contract

- The user is responsible for initial coarse centering and focusing.
- The software must autofocus before taking a new XY reference image. The
  reference is the registration template, so a blurred reference poisons every
  later offset fit.
- XY offset fitting uses an autofocus ROI in camera coordinates. The ROI should
  be drawn in live view for operator clarity, but the autofocus instrument owns
  how that ROI is used.
- The image convention presented to the user is camera-like: x is horizontal,
  y is vertical, and the displayed y axis follows the usual image direction.
  The raw frame does not need to be flipped for every acquisition.
- During diagnostic calibration, do not downsample offset fits until the
  failure modes are understood. Downsampling can be reintroduced only after it
  is shown not to change the fitted displacement or fit-quality gates.

## XY Calibration Design

- A microstep is one ANC stick-slip step. A macrostep is a finite command of
  multiple microsteps; current diagnostics use 4 microsteps per probe command
  to make the displacement measurable without pushing features out of the ROI.
- Calibration should collect paired + and - macrostep probes at a common
  voltage for a given axis. The displacement samples are measured from images;
  the pair is not assumed to return to zero.
- Probe drift must be bounded. After a probe pair, if the image fit is
  trustworthy and the sample has drifted far enough to matter, return toward
  the pre-probe position before trying the next voltage. Letting residual drift
  accumulate is unsafe because + and - stick-slip responses do not average to
  zero reliably.
- If a probe defocuses the image, autofocus should run before the next
  displacement measurement. Low image-fit R^2 during calibration should be
  treated as evidence that focus, ROI coverage, or probe size is no longer
  acceptable.
- X calibration failure should abort the diagnostic run immediately. Running Y
  after X has already walked the sample out of the reference geometry produces
  misleading data.
- The voltage-response fit should use only accepted above-threshold samples.
  Very small responses are part of the turn-on search, not the active linear
  region.

## Correction Design

```matlab
rawSteps = -(xyPixelPerStepMatrix \ offset_px);          % full model-predicted correction
rawSteps = rawSteps * min(1, maxCorrectionNorm_px / norm(offset_px));  % displacement cap
steps    = round(rawSteps);                              % integer commands only
```

The correction phase can use the final calibrated + or - operating voltage for
the sign of the command. Calibration is still responsible for keeping the
response matrix fresh; the correction loop should not silently rescale the
matrix from a single noisy correction move.

### Deadband / Tolerance Geometry

- `round` emits zero on an axis iff the offset component along that positioner
  axis is less than 0.5 target microstep.
- With a 0.5 px target step, the single-axis deadband is 0.25 px. For two
  near-orthogonal axes, the corner norm is about `0.25 * sqrt(2) = 0.354 px`.
- A practical done tolerance needs headroom above this quantization floor
  because the fitted offset and the realized step size are both noisy.

## Stability

Let `r = true_px_per_step / calibrated_px_per_step`. With full-gain correction,
the one-axis residual evolves approximately as:

```matlab
offset_next = (1 - r) * offset
```

- `r < 1`: monotone geometric convergence.
- `1 < r < 2`: sign-alternating convergence.
- `r >= 2`: deterministic ping-pong or growth unless stochastic landing noise
  happens to enter the done tolerance.

The right response to a stale or badly fitted matrix is recalibration, not an
in-loop gain that hides an incorrect calibration.

## Temperature Ramp Contract

- T/B set operations through the virtual instrument are blocking by design.
  Reaching the requested T/B value is necessary but not sufficient; the loop
  must also wait for thermal and mechanical drift to settle.
- Continuous compensation should run during T/B ramps and during cooldown,
  because waiting until the end turns a fine correction problem into a wide
  search problem.
- The instrument needs an explicit "take reference here" operation. That call
  defines the image/position/focus state to maintain during later ramps.
