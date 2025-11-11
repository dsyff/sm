# sm 1.5 - MATLAB Measurement Automation System

## 🚀 QUICK START:
- Clone or download the `sm-dev` repository (or the latest `sm-main` release) to your desktop
- Run `demos/demo.m` for complete example
- The familiar GUI interface is largely unchanged from the original system
- Use `smget("channel")` and `smset("channel", value)` for quick access
- Use `smplot("filename.mat")` to recreate plots

## 🔬 AVAILABLE INSTRUMENTS:
- **BK889B** - LCR meter
- **E4980AL** - Precision LCR meter  
- **K2400, K2450** - Keithley
- **K10CR1** - Thorlabs cage rotator
- **AndorCCD** - SDK2-compatible CCD spectrometer with accumulate mode
- **Montana2, Opticool** - Cryostats
- **SR830, SR860** - Stanford Research lock-in amplifiers
- **strainController** - Parallel strain control system
- **clock, counter** - Timing and counting

## 🔑 KEY CONCEPTS:
- **Batch Optimization**: getWrite/getRead separation and smart ordering for performance
- **Avoid Nested rackGet**: Never trigger a `rackGet` from inside another `rackGet` (e.g., via virtual instruments) because `getWrite`/`getRead` pairs must stay back-to-back for each channel—MATLAB will throw a descriptive error if they are interleaved
- **Bridge System**: Seamless compatibility between old/new instruments
- **Vector Channels**: Multi-element channels (e.g., XY, XTheta, YTheta, RTheta) supported in smgui and instruments (get only, no vector setting)
- **Data Compatibility**: Same file format as legacy system - existing analysis code works unchanged
- **Virtual Instruments**: Create complex scans (non-linear ramping) and parameter conversions (field→gate voltages)
	- Base class `virtualInstrumentInterface` lives in `code/sm2`; concrete helpers in `code/instruments` should follow the layout shown in `instrument_demo.m`.
- **Deterministic Plot Axes**: Real-time 1D plots always use the loop where a channel is acquired for the x-axis; 2D plots demand that loop be ≤ `nloops-1` and pick a distinct remaining loop for the y-axis (raising errors when a second loop is unavailable).

## 🔧 TROUBLESHOOTING:
- Check instrument addresses and VISA connections
- Verify channel names match exactly (case-sensitive)
- Use `smplot()` to recover plots from saved data
- Check `filename-tempN.mat~` files if scan interrupted

---

📖 **For complete documentation, see [README_LONG.md](README_LONG.md)**  
📅 **Last Updated**: 2025-11-11
