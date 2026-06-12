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

## Known Implementation Drift

These are quick reminders from earlier code review. Production autofocus code
is intentionally not being updated during the current Z-voltage test pass.

- The production reference path may not autofocus immediately before capturing
  the XY reference, even though this document requires it.
- Current pairwise diagnostics use 4-microstep XY probes. Production code may
  still use a different probe macrostep count.
- The production autoshift path should be rechecked for whether it captures
  and validates the offset-fit goodness-of-fit object before using it.

## Hardware Behavior

- The ANC300 stick-slip axes have a two-segment voltage response. Below a
  turn-on voltage, commanded steps produce little or no motion. Above turn-on,
  the mean image displacement per microstep is approximately linear in voltage:
  `px_per_step = slope * V + intercept`.
- Near turn-on, percentage scatter is large. A voltage that is useful for
  detecting motion may still be too noisy for accurate correction.
- The low-response region should not be treated as part of the active
  calibration line. Very small measured responses are turn-on diagnostics;
  they are useful for moving the intercept but should not pull the active
  slope down.
- Oversized XY probes are self-defeating. Recent no-optics data showed that
  aiming for 2 px/microstep can push the image 20-30 px during a 4-step probe,
  degrading the registration fit and forcing slow voltage walk-down retries.
  Moderate targets around 0.75, 1, 1.25, and 1.5 px/microstep are a better
  compromise: above the noisy 0.5 px region, but below the large-shift regime.
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
- Diagnostic runs may downsample offset fits for speed only when the fitted
  displacement and fit-quality gates remain consistent with full-resolution
  fits. Fit-quality gates must be revisited whenever downsampling changes.

## XY Calibration Design

- A microstep is one ANC stick-slip step. A macrostep is a finite command of
  multiple microsteps; current diagnostics use 4 microsteps per probe command
  to make the displacement measurable without pushing features out of the ROI.
- Calibration should collect paired + and - macrostep probes at a common
  voltage for a given axis. The displacement samples are measured from images;
  the pair is not assumed to return to zero.
- Pairwise diagnostic calibration should measure each + or - macrostep against
  the immediately preceding image, not against the original reference. The
  cumulative drift vector should still be tracked; once one axis has a trusted
  calibration, compensate the accumulated drift before moving to the next axis.
  Production compensation can be more conservative and return more often if
  fit quality or ROI coverage degrades.
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
- Current calibration should estimate one operating voltage per physical axis,
  using both + and - samples at the same voltage. Direction-split voltages
  should remain a later optimization unless the accepted data form reproducible
  + and - clusters.
- The correction target can stay at 0.5 px/microstep even if the calibration
  probes use larger targets. In that case the 0.5 px operating voltage is an
  extrapolation from the accepted active-line fit, not a direct noisy probe.

## Z Voltage Calibration Design

- Z needs its own voltage calibration before XY calibration and before any
  T/B ramp compensation. The goal is only detectable Z motion, not best focus.
- The diagnostic test for this stage is
  `tests/autofocus testing/attodry_z_tenengrad_macrostep_scan.m`. It should
  use 4-microstep Z macrosteps and scan a voltage range high enough to bracket
  the turn-on region.
- A usable Z-voltage gate should be based on Tenengrad noise measured from
  repeated no-motion images at the same voltage. The calibrated voltage should
  be accepted only when a zero-net Z oscillation produces a Tenengrad response
  that clears that gate.
- The zero-net oscillation pattern for calibration should be symmetric, for
  example `+N, -2N, +N`, so the voltage probe does not intentionally walk away
  from the starting focus position.
- Once a Z voltage is calibrated, normal autofocus can use that voltage to
  search for the local focus optimum. Voltage calibration and focus optimization
  should stay separate because they answer different questions.

## Correction Design

```matlab
rawSteps = -(xyPixelPerStepMatrix \ offset_px);          % full model-predicted correction
rawSteps = rawSteps * min(1, maxCorrectionNorm_px / norm(offset_px));  % displacement cap
steps    = round(rawSteps);                              % integer commands only
```

The correction phase uses the final calibrated operating voltage for each
axis. Calibration is still responsible for keeping the response matrix fresh;
the correction loop should not silently rescale the matrix from a single noisy
correction move.

The correction done gate must require a trustworthy offset fit. A small fitted
offset with poor R^2 is not evidence of convergence; it is an invalid
measurement and must not be accepted as `done` or `loose_done`.

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
