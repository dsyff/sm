# SM 1.5 - MATLAB Measurement Automation System

## 🚀 QUICK START:
- Run `demos/demo.m` for complete example
- Use `smrun_new(smscan, "filename")` for scanning
- Use `smget("channel")` and `smset("channel", value)` for quick access
- Use `smplot("filename.mat")` to recreate plots

## 🔑 KEY CONCEPTS:
- **Virtual Instruments**: Create complex scans (non-linear ramping) and parameter conversions (field→gate voltages)
- **Batch Optimization**: getWrite/getRead separation for performance
- **Timing Intelligence**: Automatic response time measurement and smart ordering
- **Bridge System**: Seamless compatibility between old/new instruments
- **Vector Channels**: New instruments support multi-element channels (bridge pending)
- **Data Compatibility**: Same file format as legacy system - existing analysis code works unchanged

## 📁 CORE FILES:
- `smrun_new.m` - Main scanning function (10-15% faster than legacy)
- `smget.m`, `smset.m` - Quick channel access (convenience wrappers)
- `instrumentInterface.m` - Base class for all new instruments
- `instrument_demo.m` - Template for creating new instruments

## 🔬 INSTRUMENT EXAMPLES:
- **SR830, SR860** (lock-in amplifiers) - fully migrated
- **K2400, K2450** (voltage sources) - working implementations

## ⚡ PERFORMANCE TIPS:
- Always use `smrun_new()` instead of legacy `smrun()`
- Pre-configure instruments before scanning
- Use appropriate `waittime` for instrument settling
- Monitor real-time progress in figure 1000

## 🔧 TROUBLESHOOTING:
- Check instrument addresses and VISA connections
- Verify channel names match exactly (case-sensitive)
- Use `smplot()` to recover plots from saved data
- Check `filename-tempN.mat~` files if scan interrupted

## 📊 MIGRATION STATUS:
- ✅ **SR830, SR860** - Complete with batch optimization
- ✅ **strainController** - Complete parallel control system (migrated from v1.3)
- 🔄 **Additional instruments** - In progress (see README.md)

---

📖 **For complete documentation, see [README.md](README.md)**  
📅 **Last Updated**: 2025-07-17
