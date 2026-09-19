# CS165 camera runtime

This folder supplies the shared acquisition runtime for `instrument_CS165MU`
and `instrument_CS165CU`. It is a selected runtime bundle, not the complete
Thorlabs processing SDK. The driver loads `Thorlabs.TSI.TLCamera.dll` and
`Thorlabs.TSI.TLCameraInterfaces.dll` by absolute path and puts this folder on
the process DLL search path.

## Omitted processing libraries

The following optional libraries are not used by either driver:

| File | Bytes omitted |
| --- | ---: |
| `thorlabs_tsi_color_processing.dll` | 56,989,184 |
| `thorlabs_tsi_color_processing_vector_avx2.dll` | 92,042,240 |
| `thorlabs_tsi_polarization_processor.dll` | 14,533,120 |
| `thorlabs_tsi_polarization_processor_vector_avx2.dll` | 8,218,624 |
| `thorlabs_tsi_polarization_processor_vector_avx512.dll` | 9,121,280 |
| **Total** | **180,904,448 (172.52 MiB)** |

The MU driver reads raw frames. The CU subclass extracts Bayer planes and
constructs red/green/blue/gray/RGB images in MATLAB; it does not call the vendor
color processor. Neither driver uses polarization processing.

An audit of the bundled DLLs' native imports, delay imports, managed references,
P/Invoke targets, and embedded DLL names found no dependency from acquisition
to these five libraries. Their callers are the optional ColorProcessor,
PolarizationProcessor, and native mono-to-color processing APIs. Thorlabs'
[color example](https://github.com/Thorlabs/Camera_Examples/blob/main/MATLAB/Compact_Scientific_Cameras/SoftwareTrigger.m)
and [polarization example](https://github.com/Thorlabs/Camera_Examples/blob/main/MATLAB/Compact_Scientific_Cameras/PolarizationProcessing.m)
also initialize the processing APIs separately from the camera SDK.

Keep the small `Thorlabs.TSI.ColorInterfaces.dll` and
`Thorlabs.TSI.PolarizationInterfaces.dll`: the TLCamera assemblies reference
them even for raw acquisition. The remaining small assemblies, native transport
libraries, and configuration are retained. Their combined size is 2,954,820
bytes (2.82 MiB), excluding this document. If a future driver uses vendor color
or polarization processing, restore the matching processing libraries from the
same SDK version before enabling that API.

## Validation boundary

MATLAB R2025b Update 1 successfully loaded the assemblies, opened the SDK,
discovered devices, and disposed the SDK in separate fresh processes before and
after the removal. Both runs found zero cameras and loaded the same native
camera modules from this folder. Both emitted the existing EDT no-board
diagnostic. No physical camera was opened and frame acquisition was not tested.

Removing these files reduces current checkouts and source archives. Existing
Git history still contains the original binaries; no history rewrite is needed
or performed for this cleanup.
