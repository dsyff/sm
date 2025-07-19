# sm 1.5 - MATLAB Measurement Automation System

## 🚀 QUICK START:
- Download and extract `sm-main` folder to desktop
- Run `demos/demo.m` for complete example
- The familiar GUI interface is largely unchanged from the original system
- Use `smget("channel")` and `smset("channel", value)` for quick access
- Use `smplot("filename.mat")` to recreate plots

## 🔬 AVAILABLE INSTRUMENTS:
- **BK889B** - LCR meter
- **E4980AL** - Precision LCR meter  
- **K2400, K2450** - Keithley
- **Montana2, Opticool** - Cryostats
- **SR830, SR860** - Stanford Research lock-in amplifiers
- **strainController** - Parallel strain control system
- **clock, counter** - Timing and counting

## 🔑 KEY CONCEPTS:
- **Batch Optimization**: getWrite/getRead separation and smart ordering for performance
- **Bridge System**: Seamless compatibility between old/new instruments
- **Vector Channels**: Multi-element channels (e.g., XY, XTheta, YTheta, RTheta) supported in smgui and instruments (get only, no vector setting)
- **Data Compatibility**: Same file format as legacy system - existing analysis code works unchanged
- **Virtual Instruments**: Create complex scans (non-linear ramping) and parameter conversions (field→gate voltages)

## 🔧 TROUBLESHOOTING:
- Check instrument addresses and VISA connections
- Verify channel names match exactly (case-sensitive)
- Use `smplot()` to recover plots from saved data
- Check `filename-tempN.mat~` files if scan interrupted

---

📖 **For complete documentation, see [README_LONG.md](README_LONG.md)**  
📅 **Last Updated**: 2025-07-19
