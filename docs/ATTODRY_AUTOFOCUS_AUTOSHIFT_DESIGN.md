# Attodry Autofocus XY Autoshift — Control Design

Design rationale for the XY drift-correction (autoshift) loop in
`virtualInstrument_attodryAutofocus`. Records why the loop is full-gain with
quantized steps, how the done tolerance is derived, and what to preserve when
extending to varying temperature. Last updated 20260610.

Code map:
- Instrument: `code/instruments/@virtualInstrument_attodryAutofocus/virtualInstrument_attodryAutofocus.m`
  (`runAutoshift`, `calibrateXYPixelPerStepMatrix`, `waitForTargetsWithCompensation`)
- Standalone mirrors (git-ignored debug scripts): `tests/autofocus testing/`
  (`attodry_no_optics_positioner_smoke_test.m`: `calibrateXY`, `returnToReference`;
  `attodry_z_tenengrad_macrostep_scan.m`: Z response diagnostic)

## 1. Actuator physics (ANC300 stick-slip positioners)

- Below a threshold ("turn-on") voltage an axis does not step at all.
- Above threshold, mean px/step grows roughly linearly with voltage
  (slope + intercept = the "active line", stored per temperature in
  `attodry_autofocus_positioner_voltage_profile.csv`).
- Near threshold the realized step size is very noisy in percentage terms,
  and + / - directions are asymmetric.
- Consequence: ~0.5 px/step (`targetStepSizePixel`) is the smallest reliable
  quantum. Calibration probes 0.5 / 1 / 1.5 px/step targets along the active
  line and shifts the turn-on estimate when the response is dead or huge.

## 2. Calibration output

- Per axis: active line (slope, intercept) refit from oscillation probes;
  accepted when the predicted target voltage is stable between probe batches
  (`xyCalibrationBatchVoltageToleranceFraction`).
- `xyPixelPerStepMatrix`: each column is the unit response direction scaled to
  exactly `targetStepSizePixel`, mapping integer steps [x; y] to expected
  [row; col] px. Conditioning is enforced via `xyResponseMatrixMinRcond`.
- Drift handling during calibration (smoke test 20260610, instrument port
  pending): probes are not stepped back after measurement. Probe direction
  defaults to +/- balance but flips to oppose the measured drift (++/--
  allowed), so the descending-step-size probe batches compensate
  progressively better as the active line improves. Drift beyond 5 px
  projected on the axis triggers a single multi-step command at the
  active-line `targetStepSizePixel` voltage.
- Calibration offset fits run on a 2x-per-axis downsampled sample grid (4x
  fewer residuals); correction-phase fits stay full resolution.

## 3. Correction law

```
rawSteps = -(xyPixelPerStepMatrix \ offset_px);          % full model-predicted correction
rawSteps = rawSteps * min(1, maxCorrectionNorm_px / norm(offset_px));  % 20 px displacement cap
steps    = round(rawSteps);                              % integer commands only
```

The displacement cap (smoke test 20260610) replaces the older per-axis clamp
(1-2 steps per command, then `maxAutoshiftCorrectionStepsPerAxis`), which made
large recoveries needlessly slow (a 22 px offset took 13 iterations at +/-2).
The instrument still carries the per-axis clamp until the port.

There is deliberately NO gain/damping factor (`autoshiftStepRatio` was removed
20260610). With integer commands a gain < 1 cannot produce sub-quantum motion;
near convergence the command is 0 or +/-1 either way. The only end-game effect
of a 0.5 gain was to double the round-to-zero deadband from +/-0.25 px to
+/-0.5 px per axis, leaving a stuck annulus between deadband and tolerance.

### Deadband / tolerance geometry

- `round` emits zero on an axis iff the offset component along that positioner
  axis is < 0.5 * targetStepSizePixel = 0.25 px (MATLAB rounds half away from
  zero, so exactly one step's worth still commands a full step).
- Worst case both components just under 0.25 px: offset norm
  0.25 * sqrt(2) ~= 0.354 px (axes near-orthogonal; rcond check guards this).
- `autoshiftTightTolerancePixel = autoshiftToleranceFactor * targetStepSizePixel / sqrt(2)`
  with factor default 1.5 (~0.53 px). Factor 1 would sit exactly at the
  quantization floor, but then a residual landing near the worst-case corner
  passes only by lottery (run 20260610_175001 finished at 0.370 px vs floor
  0.354 px and needed the loose path). Factor 1.5 adds headroom for image-fit
  noise and the stochastic landing spread while still implying a [0, 0]
  command ends within tolerance.
- `autoshiftLooseTolerancePixel = sqrt(2) * tight` (~0.75 px at defaults):
  loose accept after `autoshiftLooseSuccessStepBudget` (20) moves; forced
  recalibration after `autoshiftRecalibrationStepBudget` (50) moves while
  still outside loose.

## 4. Stability

Let r = (true px/step) / (calibrated px/step) at correction time. Per cycle,
along each axis direction:

```
offset_next = (1 - r) * offset        % full gain
```

- r < 1: monotone geometric convergence (always safe, just slower).
- 1 < r < 2: sign-alternating convergence.
- r = 2: deterministic ping-pong, no convergence.
- r > 2: deterministic growth until the displacement cap bounds it.

Why this is acceptable without damping:

1. r ~= 1 by construction: correction runs shortly after calibration at the
   same conditions, and recalibration triggers keep the matrix fresh.
2. Dither rescue: near threshold the step-size noise is comparable to the
   step itself. Each +/-1 bounce has order-tens-of-percent probability of
   landing inside the absorbing tolerance circle (once inside, the loop stops
   commanding), so the stochastic loop converges almost surely even at r >= 2.
3. The regime where dither fails — mean step much larger than the tolerance
   radius with small relative spread — only occurs far above threshold, where
   calibration would never have placed the operating voltage.

Failure signature of a stale matrix (r >= 2): sign-alternating offsets with
non-decreasing magnitude across consecutive correction iterations in the
correction log. Fix by recalibrating more often, not by reintroducing a gain.

## 5. Temperature status

- Validated at fixed temperature only (as of 20260610). At fixed T, r stays
  near 1 because correction immediately follows calibration.
- Existing hooks for varying T: forced recalibration when |T - calibration T|
  exceeds `voltageProfileMinTemperatureSpacing_K` (2 K), calibration-history
  drift refresh, and the recalibration step budget.
- Main watch item for the T-expansion: the profile voltage sliding below the
  (T-dependent) turn-on threshold as T drops. The response then goes to zero
  and correction stalls rather than oscillates; this is caught by the
  low/no-response calibration paths (`xyCalibrationMinUsablePxPerStep`,
  turn-on shifting), not by anything gain-related.

## 6. Key parameters

| Parameter | Value | Meaning |
|---|---|---|
| `targetStepSizePixel` | 0.5 | calibrated px per microstep (minimum reliable quantum) |
| `autoshiftToleranceFactor` | 1.5 | tolerance headroom over the quantization floor |
| `autoshiftTightTolerancePixel` | factor * 0.25*sqrt(2) ~= 0.53 | done tolerance |
| `autoshiftLooseTolerancePixel` | sqrt(2) * tight ~= 0.75 | fallback acceptance after move budget |
| `autoshiftLooseSuccessStepBudget` | 20 | moves before loose acceptance allowed |
| `autoshiftRecalibrationStepBudget` | 50 | moves before forced recalibration |
| `maxCorrectionNorm_px` | 20 | per-command predicted displacement cap (smoke test) |
| `voltageProfileMinTemperatureSpacing_K` | 2 | T drift that forces recalibration |
