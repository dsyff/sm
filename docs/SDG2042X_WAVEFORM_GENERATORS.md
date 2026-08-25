# SDG2042X DDS and TrueARB waveform generators

This guide describes the three SDG2042X instrument classes currently provided by `sm-dev`:

| Class | Generator mode | Waveform organization |
| --- | --- | --- |
| [`instrument_SDG2042X_mixed`](../code/instruments/instrument_SDG2042X_mixed.m) | DDS/ARB frequency mode | Up to 25 tones summed into one waveform and used by both physical outputs |
| [`instrument_SDG2042X_pure`](../code/instruments/instrument_SDG2042X_pure.m) | DDS/ARB frequency mode | Two independent pure lock-in reference tones, one per physical output |
| [`instrument_SDG2042X_mixed_TARB`](../code/instruments/instrument_SDG2042X_mixed_TARB.m) | TrueARB sample-rate mode | Up to 25 tones summed into one waveform and used by both physical outputs |

The mixed DDS and mixed TARB classes are alternative ways to drive a mixed waveform. The pure instrument is intended to feed lock-in amplifier reference inputs: tone 1 is output on C1 and tone 2 on C2. The canonical recipe setup is in [`demos/demo.m`](../demos/demo.m).

## Constructor settings

All three constructors accept the same settings:

```matlab
instrument_ClassName(address, ...
    waveformArraySize = 2e5, ...
    uploadFundamentalFrequencyHz = 1, ...
    internalTimebase = true)
```

| Setting | Meaning |
| --- | --- |
| `address` | VISA resource string passed to `visadev`. The VISA terminator is configured as LF. |
| `waveformArraySize` | Positive integer number of uploaded `int16` waveform samples. |
| `uploadFundamentalFrequencyHz` | Positive fundamental frequency `f0`. One uploaded waveform spans `1/f0` seconds. |
| `internalTimebase` | Selects the internal (`true`) or external (`false`) reference oscillator. In the DDS classes it also selects CASCADE master or slave mode. |

The class defaults are shown above. The demo uses `2^15` samples for both DDS instruments and `2^20` samples for TARB. These values are waveform point counts, not DAC bit depths. They are the largest sizes verified on the project hardware: oscilloscope tests showed malformed output when larger arrays were used. Treat `2^15` for DDS and `2^20` for TARB as safe upper limits for the tested SDG2042X hardware/firmware, and do not increase `waveformArraySize` unless the resulting output is verified on an oscilloscope under the intended operating conditions. These empirical limits are stricter than the [SDG2000X datasheet](https://siglentna.com/wp-content/uploads/dlm_uploads/2025/11/SDG2000X_DataSheet_EN02H.pdf), which specifies 16-bit vertical resolution and a general arbitrary-waveform length of 8 to 8M points.

For TARB, the configured sample rate is

```text
sample rate = waveformArraySize * uploadFundamentalFrequencyHz
```

and must be less than `1.2e9` samples/s. All three upload paths reject a final binary command larger than 16 MiB.

Constructing any of these classes sends `*RST`, applies the static generator configuration, uploads an initial zero waveform, and enables the relevant outputs. Construction therefore reconfigures the connected generator.

## Waveform and frequency convention

For tone `k`, the requested signal is constructed as

```text
x_k(t) = amplitude_k / 2 * sin(2*pi*frequency_k*t
                               + (phase_k + global_phase_offset)*pi/180)
```

`amplitude_k` is in Vpp, `frequency_k` is in Hz, and both phase values are in degrees. The mixed classes sum all 25 cached tones. The pure class constructs one waveform from tone 1 for C1 and a separate waveform from tone 2 for C2.

The sample times cover one fundamental period:

```text
fs = waveformArraySize * uploadFundamentalFrequencyHz
t  = (0:waveformArraySize-1) / fs
```

For a seamless, spectrally pure repeating waveform, choose tone frequencies that are integer multiples of `uploadFundamentalFrequencyHz`.

Before upload, each waveform has its residual numerical mean removed. It is then normalized to the signed 16-bit DAC range, while the generator amplitude is set so that the physical output retains the requested voltage scale. The DDS implementations apply their internal amplitude multiplier when sending the final `BSWV AMP` command; rack-facing amplitudes remain Vpp and should not be pre-scaled.

## Channels

The mixed DDS and mixed TARB instruments always register:

- `amplitude_1` through `amplitude_25` in Vpp
- `phase_1` through `phase_25` in degrees
- `frequency_1` through `frequency_25` in Hz
- `global_phase_offset` in degrees

The pure DDS instrument registers the same channel types for tones 1 and 2 only, plus `global_phase_offset`.

Each class keeps two separate caches: the requested target settings and the settings last applied successfully to the generator. Channel reads return the latter; they do not query or decode generator waveform memory.

`setWrite` only changes the target cache. The first subsequent `setCheck` reconciles all pending changes:

- In a mixed class, one complete mixed waveform is rebuilt and uploaded, regardless of how many tone fields changed.
- In the pure class, each physical channel with a changed tone is uploaded once. Changing `global_phase_offset` uploads C1 and C2 because it affects both waveforms.
- After the upload, both outputs must report `ON` before the applied-settings cache is advanced. Later checks in the same multi-channel rack batch compare caches and perform no I/O.

Keep `requireSetCheck = true` for these classes. If it is `false`, the framework intentionally skips `setCheck`; `setWrite` then records pending targets but does not apply them to the generator.

## DDS and TARB configuration

Both modes configure C1 and C2 as ARB outputs, use high-impedance load mode, and set the hardware offset and phase to zero because offset and phase are encoded in the uploaded samples.

### DDS mode

The mixed and pure DDS classes configure:

```text
C1/C2:SRATE MODE,DDS
C1/C2:BSWV FRQ,<uploadFundamentalFrequencyHz>
```

The waveform is still transferred as binary ARB data. The `BSWV FRQ` setting controls the repetition rate of the uploaded period. The source comments note that some SDG firmware may not accept the explicit `SRATE MODE,DDS` command.

### TrueARB mode

The mixed TARB class configures:

```text
C1/C2:SRATE MODE,TARB
C1/C2:SRATE VALUE,<waveformArraySize * uploadFundamentalFrequencyHz>
```

In this mode the explicit sample rate controls playback. Hardware testing for this setup found that TARB could not be used for master/slave CASCADE synchronization, so the TARB class deliberately does not configure CASCADE; use the DDS classes when multiple generators must be synchronized. Siglent's [multi-generator synchronization note](https://siglentna.com/application-note/multi-generator-synchronization/) does not qualify synchronization by playback mode, so treat this as an empirical limitation of the tested SDG2042X hardware/firmware rather than a universal vendor specification.

## Physical-output behavior

For both mixed classes:

1. All rack `setWrite` calls record targets without touching the outputs.
2. On the first `setCheck`, C1 and C2 are turned off for the update.
3. One mixed waveform is synthesized and uploaded under a single waveform name.
4. The waveform is selected on both physical outputs and their amplitudes are updated.
5. C1 and C2 are turned on together and checked before the applied-settings cache is advanced.

C2 is configured with inverted polarity after reset, while C1 retains normal polarity.

The pure class maintains a separate waveform name for each physical output and only turns off a channel whose target changed. Both physical outputs must report `ON` after an upload before the set check passes. This confirms output state only; the applied tone settings remain a record of successful commands, not waveform or amplitude readback.

## DDS timebase and CASCADE setup

The DDS classes set both channels to the selected reference oscillator and configure CASCADE after the first waveform upload. This ordering is intentional because the code comments record more reliable behavior on some firmware when waveform memory is initialized first.

- `internalTimebase = true` selects the internal oscillator and CASCADE `MASTER` mode.
- `internalTimebase = false` selects the external oscillator and CASCADE `SLAVE` mode.

`cascadeResyncOnMaster()` forces a remote synchronization by cycling CASCADE off and on. It acts only on a DDS object configured as the master. The demo calls this after both the mixed DDS master and pure DDS slave have been initialized.

## Selecting rack-visible mixed tones

The mixed instruments always expose all 25 tones internally. The top-level `n_tones` setting in `demos/demo.m` controls only how many tone triplets are added to the rack:

```matlab
n_tones = 10; % 1-25

for i = 1:n_tones
    recipe.addChannel("SDG2042X_mixed", "amplitude_" + string(i), "mix_A_" + string(i));
    recipe.addChannel("SDG2042X_mixed", "phase_" + string(i), "mix_Th_" + string(i));
    recipe.addChannel("SDG2042X_mixed", "frequency_" + string(i), "mix_f_" + string(i));
end
recipe.addChannel("SDG2042X_mixed", "global_phase_offset", "mix_Th");
```

The demo throws an error unless `n_tones` is an integer from 1 through 25. The TARB block uses the same setting with `mixTARB_*` friendly names. The pure instrument always adds its two physical tone groups and does not use `n_tones`.

## Operational notes

- A set-write is a lightweight target-cache update. The set-check phase performs the required waveform upload; both mixed outputs are briefly disabled once for the complete pending batch.
- The instrument classes set `writeCommandInterval = seconds(5)` as a conservative communication-stability guard. SDG cache-only set-writes and already-reconciled set-checks opt out of that gate, so a large tone batch is not serialized by 5-second waits. The gate still applies to set-checks that perform an upload, and it paces the framework transaction rather than every internal SCPI line; see [Measurement engine architecture](MEASUREMENT_ENGINE_ARCHITECTURE.md).
- Cached channel reads report the last successfully applied settings but do not prove the present hardware waveform if the generator was changed outside this class.
- Use integer multiples of the upload fundamental to avoid a discontinuity at the waveform boundary.
- Keep `waveformArraySize * uploadFundamentalFrequencyHz < 1.2e9` when using TARB.
- If DDS initialization fails specifically on `SRATE MODE,DDS`, check the connected unit's firmware support for that command.
