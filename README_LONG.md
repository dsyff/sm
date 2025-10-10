# special measure 1.5 (sm1.5) - README

## 🚀 QUICK START

1. Launch MATLAB and navigate to SM1.5 folder
2. Run `smgui_small_new` for basic scanning interface
3. Create instruments: `sr830 = instrument_SR830("GPIB::8::INSTR")`
4. Configure scans using GUI or programmatically
5. Execute with `smrun_new(smscan, "filename")`
6. View results with `smplot("sm_filename.mat")`

## 📋 OVERVIEW

sm1.5 is a MATLAB-based measurement automation system for scientific instruments.
It combines the legacy special measure (sm) system with a new object-oriented 
framework (instrumentInterface and instrumentRack) for improved performance, 
maintainability, and features.

**Key Benefits:**
- 10-15% faster scanning than legacy system
- Object-oriented instrument management
- Batch-optimized communications (getWrite/getRead separation)  
- Real-time plotting with automatic figure management
- Robust error handling and recovery
- PowerPoint integration for automated reporting

## 🏗️ SYSTEM ARCHITECTURE

### 1. LEGACY SYSTEM (smlegacy/)
**Original special measure code - still functional**
- Uses global `smdata` structure for instrument configuration
- Channel-based access with numeric indices  
- Files: `sm.m` (main GUI), `smrun.m` (scanning engine)
- **Status**: Maintained for compatibility but not actively developed

### 2. NEW SYSTEM (sm2/, instruments/) 
**Modern object-oriented approach - recommended for new work**
- `instrumentInterface.m`: Abstract base class for all instruments
- `instrumentRack.m`: Manages collections of instruments
- Separated getWrite/getRead and setWrite/setCheck for optimized batch operations
- Strong typing, input validation, and comprehensive error handling
- **Status**: Active development, all new instruments use this system

### 3. BRIDGE SYSTEM (smbridge/) 
**Connects old and new systems seamlessly**
- `smrun_new.m`: Optimized scanning engine (10-15% faster than legacy)
- `smget_new.m`, `smset_new.m`: Channel access functions with new backend
- `smgui_small_new.m`: Streamlined GUI interface
- **Status**: Production ready, recommended for all scanning operations

## 📁 KEY FILES AND FUNCTIONS

### CORE SCANNING:
- **`smrun_new.m`**: Main scan execution with real-time plotting and data saving
- **`smplot.m`**: Recreate plots from saved data files  
- **`smgui_small_new.m`**: GUI for scan configuration (101 points default, saveloop=2)
- **`sm.m`**: Legacy GUI for storing scan collections and queueing execution

### CHANNEL ACCESS:
- **`smget.m`**: Quick channel reading (wrapper for `smget_new.m`)
- **`smset.m`**: Quick channel setting (wrapper for `smset_new.m`)
- **`smget_new.m`**: Full-featured channel reading with batch optimization
- **`smset_new.m`**: Full-featured channel setting with verification

### INSTRUMENT INTERFACE:
- **`instrumentInterface.m`**: Abstract base class (see IMPORTANT CONCEPTS below)
- **`instrument_*.m`**: Specific instrument implementations (SR830, SR860, K2400, etc.)
- **`instrumentRack.m`**: Manages multiple instruments with batch optimization
- **`gpibAddress.m`**: GPIB address management utilities

### DATA MANAGEMENT:
- **Auto-saves**: `.mat` files with scan configuration, data, and metadata
- **PowerPoint integration**: via `smsaveppt.m` for automated reporting
- **Temporary files**: `filename-tempN.mat~` for scan recovery
- **Figure export**: Auto-saves as `.fig` and `.pdf` formats
- **Format compatibility**: sm1.5 outputs data files in the same format as legacy system - existing data processing code works without modification

## 🔑 IMPORTANT CONCEPTS

### 1. VIRTUAL INSTRUMENTS 🔄
**Create complex measurement patterns and parameter conversions**

Virtual instruments are software-only instruments that control other instruments or perform calculations. They enable:

- **Non-linear scan ramping**: Virtual instrument that applies mathematical functions to create logarithmic, exponential, or custom scan patterns
- **Parameter conversion**: Convert high-level parameters (electric field, doping) into low-level hardware controls (gate voltages)  
- **Multi-instrument coordination**: Single virtual channel that synchronizes multiple physical instruments
- **Complex measurement sequences**: Virtual instruments that orchestrate sophisticated measurement protocols

**Example use cases:**
```matlab
% Virtual instrument for electric field control
% Converts field requests into top/bottom gate voltages
virtualField = instrument_VirtualField(topGateKeithley, bottomGateKeithley, tophBN, bottomhBN);

% Virtual instrument for non-linear ramping  
% Creates logarithmic voltage sweeps by controlling a voltage source
virtualLogRamp = instrument_VirtualLogRamp(keithley2400, startV, endV);
```

**Implementation notes:**

- The abstract base lives at `code/sm2/virtualInstrumentInterface.m`; concrete virtual instruments belong in `code/instruments/` alongside physical drivers.
- Use `instrument_demo.m` as the formatting template—keep constructors concise, rely on default tolerances from `addChannel`, and only override `setCheckChannelHelper` when you need behaviour beyond the rack's default verification.

### 2. GETWRITE/GETREAD SEPARATION 🚀
**The key performance optimization in SM1.5**

```
Traditional:  [cmd1→read1] → [cmd2→read2] → [cmd3→read3]  (serial)
sm1.5:        [cmd1, cmd2, cmd3] → [read1, read2, read3]   (parallel)
```

- **getWrite**: Send all measurement commands simultaneously
- **getRead**: Read all responses after instruments have settled
- **Result**: Minimizes total measurement time, especially for slow instruments
- **Implementation**: All new instruments must implement both methods

**Intelligent Timing Optimization:**
- **Response Time Measurement**: During `addChannel()`, system measures each channel's 
  response delay (5 trials, median time) and stores in `getReadTimes`
- **Smart Ordering**: In `rackGet()`, channels sorted by response time (longest first)
- **"First to Write, Last to Read"**: 
  - Longest delay channels get `getWrite` commands first
  - Shortest delay channels get `getRead` commands first  
  - Maximizes parallel processing while instruments settle
- **Example**: If SR830 takes 50ms and K2400 takes 10ms:
  ```
  Order of getWrite: [SR830, K2400]  ← Start slow instrument first
  Order of getRead:  [K2400, SR830]  ← Read fast instrument first
  Total time: ~50ms instead of 60ms  ← 17% improvement
  ```

#### ⚠️ Avoid Nested `rackGet` Calls
- `instrumentRack` expects every `getReadChannel` to immediately follow the matching `getWriteChannel` for the same physical channel.
- Virtual instruments that call `rackGet` (or `getChannel`) inside their own `getRead` implementation can accidentally interleave `getWrite` commands from different channels.
- Many hardware drivers assume the last serial command they issued still matches the pending read. If another instrument sneaks in a `getWrite`, the response buffer becomes invalid.
- `instrumentInterface` detects this mismatch and throws a descriptive error rather than failing silently; a newcomer might hit this error without understanding the root cause.
- **Never** perform a nested `rackGet` from inside an instrument method. Instead, split complex measurements into independent channels or prefetch the required values before the outer `rackGet` begins.

### 3. SETWRITE/SETCHECK SEPARATION ⚡
**Batch optimization for setting instrument parameters**

```
Traditional:  [set1→check1] → [set2→check2] → [set3→check3]  (serial)
sm1.5:        [set1, set2, set3] → [check1, check2, check3]   (parallel)
```

- **setWrite**: Send all set commands to start parameter changes
- **setCheck**: Verify all values within tolerance after settling
- **Critical for**: Voltage sources, temperature controllers, frequency generators
- **Tolerance-based**: Only checks channels with defined `setTolerances`

### 3. CHANNEL NAMING AND ACCESS
- **Legacy**: Numeric indices (`smget(inst, chan)` where chan = 1,2,3...)
- **New**: String names (`smget("instrument.channel")` or `instrument.getChannel("channel")`)
- **Bridge**: Translates between systems automatically
- **Quick Access**: Use `smget()` and `smset()` for faster interactive typing
- **Best Practice**: Use descriptive names ("gate_voltage", "drain_current", etc.)

### 4. SCAN STRUCTURE AND LOOPS

```matlab
scan.loops(1).setchan = "voltage_source.voltage";    % What to sweep
scan.loops(1).rng = [0, 1];                          % Range  
scan.loops(1).npoints = 101;                         % Number of points
scan.loops(1).getchan = {"lockin.X", "lockin.Y"};    % What to measure
scan.loops(1).waittime = 0.1;                        % Settling time

% Nested loops automatically supported:
scan.loops(2).setchan = "gate.voltage";              % Outer loop
scan.loops(2).rng = [-1, 1]; 
scan.loops(2).npoints = 21;
```

### 5. TOLERANCES AND VERIFICATION

```matlab
% Define tolerances when adding channels:
obj.addChannel("voltage", setTolerances = 1e-6);     % 1µV tolerance
obj.addChannel("frequency", setTolerances = 0.01);   % 10mHz tolerance

% System automatically verifies values before continuing scan
% Prevents premature measurements on unsettled instruments
```

## ✨ RECENT OPTIMIZATIONS (2025)

### Performance Improvements:
- **10-15% faster scanning** via vectorized operations in `smrun_new.m`
- **Batch-optimized communications** with proper getWrite/getRead separation
- **Pre-computed variables** and cached validation for inner scan loops
- **Optimized figure management** (reuses figure 1000, prevents accumulation)
- **Andor CCD accumulate mode** defaults to two-frame averaging with status polling instead of blocking waits for improved robustness

### Reliability Enhancements:
- **Unique temporary file numbering** prevents overwrites during concurrent scans
- **Graceful scan exit handling** with proper cleanup on window close
- **Robust PowerPoint integration** with ActiveX compatibility fixes
- **Silent GUI operation** (removed console output for clean user experience)
- **Data format compatibility** ensures existing analysis scripts work unchanged
- **Andor CCD watchdog** replaces SDK `WaitForAcquisition` with exposure-aware polling to avoid indefinite hangs
- **K10CR1 homing logs** print informative `fprintf` messages whenever the rotator homes

### Code Quality:
- **Comprehensive error handling** with try-catch blocks and fallback mechanisms
- **Proper resource management** with automatic cleanup in destructors
- **Extensive documentation** with inline comments and usage examples
- **Vector channel support** in new instrument classes (partially implemented in smgui: only vector getting is allowed, setting is not allowed)

## 🔄 INSTRUMENT MIGRATION STATUS

### ✅ COMPLETED MIGRATIONS:
- **SR830, SR860**: Stanford Research lock-in amplifiers
  - Full getWrite/getRead separation implemented
  - **Both instruments**: Simplified request/response pattern (no buffered acquisition)
  - **SR860**: Enhanced robust retry logic exactly matching legacy behavior
    - Re-sends query commands when NaN responses received (not just re-reads)
    - Handles SR860's tendency to ignore commands with proper command retry
  - **Vector channels**: XY, XTheta, YTheta, and RTheta simultaneous reads
    - SR830 uses 1-based indexing (X=1, Y=2, R=3, Theta=4)
    - SR860 uses 0-based indexing (X=0, Y=1, R=2, Theta=3)
    - Optimized for single SCPI command efficiency with robust error handling
- **K10CR1**: Thorlabs cage rotator (position control)
  - Migrated from legacy NET-based driver with blocking move semantics
  - Provides degree-based position channel with tolerance-aware set verification
  - Automatically loads Kinesis assemblies and homes device on startup
  - Emits informative homing messages for easier lab debugging
- **AndorCCD**: Full-vertical-binning CCD spectrometer (SDK2)
  - Default configuration now uses accumulate mode with configurable `accumulations` channel
  - Exposure updates automatically invalidate cached spectra and respect status polling
  - Cosmic ray filtering enabled by default with saturation checks scaled per accumulation
  - Exposes temperature, exposure_time, accumulations, pixel_index, and counts channels aligned with demos
  - Provides `

- **strainController**: Persistent strain control system (migrated from v1.3)
  - **Parallel processing**: Real-time PID control loop running on worker thread
  - **Multi-instrument coordination**: E4980AL (LCR), K2450s (voltage sources), cryostat
  - **sm1.5 integration**: Standard channel access (`smget("strain.del_d")`) 
  - **Safety systems**: Automatic voltage ramp-down, emergency shutdown
  - **11 channels**: del_d, T, Cp, Q, C, d, V_str_o, V_str_i, I_str_o, I_str_i, activeControl
  - **Complex control**: Displacement targeting, temperature control, voltage limiting

### 🔄 IN PROGRESS:
- **Additional lock-ins**: SR844, other Stanford Research models
- **Voltage sources**: Keithley 24xx series expansion
- **Temperature controllers**: LakeShore, Oxford Instruments

### 📋 MIGRATION CHECKLIST:
For each instrument, ensure:
- [ ] Inherits from `instrumentInterface`
- [ ] Proper getWrite/getRead separation
- [ ] setWrite/setCheck for settable channels  
- [ ] Comprehensive error handling
- [ ] Descriptive channel names
- [ ] setTolerances for verification
- [ ] Documentation and examples
- [ ] Vector channel support where applicable (implemented in instruments and smgui)

### 🔮 CURRENT ENHANCEMENTS:
- **Vector Channels**: New instrument classes support vector channels for enhanced efficiency
  - Example: `obj.addChannel("XTheta", 2)` creates 2-element vector channel for simultaneous X and Theta measurements
  - Allows simultaneous multi-parameter reads in single operation
  - **Available Channels**: SR830/SR860 support XY, XTheta, YTheta, and RTheta vector channels
  - **Current Status**: Fully implemented in instruments and smgui interface
  - **Usage**: Select vector channels as "get" channels in smgui for efficient simultaneous measurements

## 💡 EXAMPLE USAGE

### Basic Instrument Control:

```matlab
% Create and configure instrument
sr830 = instrument_SR830("GPIB::8::INSTR");
smset("sr830.frequency", 1000);        % Set 1kHz reference (quick syntax)
smset("sr830.sensitivity", 1e-6);      % Set 1µV sensitivity

% Single measurements
x_signal = smget("sr830.X");            % Get X component (quick syntax)
magnitude = smget("sr830.R");          % Get magnitude
xy_data = smget("sr830.XY");           % Get both X,Y simultaneously using vector channel
xtheta_data = smget("sr830.XTheta");   % Get X and Theta simultaneously
rtheta_data = smget("sr830.RTheta");   % Get R and Theta simultaneously

% Alternative: Full function names for scripts
sr830.setChannel("frequency", 1000);        % Direct method call
x_signal = sr830.getChannel("X");            % Direct method call
xy_data = smget_new("sr830.XY");            % Full bridge function with vector channel
```

### Scan Configuration and Execution:

```matlab
% Configure a frequency sweep
clear smscan;
smscan.loops(1).setchan = "sr830.frequency";
smscan.loops(1).rng = [100, 1000];         % 100Hz to 1kHz
smscan.loops(1).npoints = 101;              % 101 points (default)
smscan.loops(1).getchan = {"sr830.XTheta", "sr830.R"}; % Use vector channel for efficiency
smscan.loops(1).waittime = 0.1;            % 100ms settling time

% Optional: Configure display
smscan.disp(1).channel = 1;                % Plot channel 1 (XTheta - returns 2-element vector)
smscan.disp(1).dim = 1;                    % 1D line plot
smscan.disp(2).channel = 2;                % Plot channel 2 (R) 
smscan.disp(2).dim = 1;                    % 1D line plot

% Execute scan
data = smrun_new(smscan, "frequency_sweep");

% Post-processing
smplot("sm_frequency_sweep.mat");          % Recreate plots
load("sm_frequency_sweep.mat");            % Load data for analysis
```

### Vector Channel Usage:

```matlab
% Efficient simultaneous measurements using vector channels
smscan.loops(1).setchan = "gate_voltage";
smscan.loops(1).rng = [-1, 1];
smscan.loops(1).npoints = 101;
% Use vector channels for efficient multi-parameter acquisition:
smscan.loops(1).getchan = {"sr830.XTheta", "sr860.RTheta", "k2400.VI"};
% XTheta returns [X, Theta], RTheta returns [R, Theta], VI returns [V, I]

% Each getchan entry creates one data column per vector element
% Data structure: [XTheta_1, XTheta_2, RTheta_1, RTheta_2, VI_1, VI_2]
%                 [   X   ,  Theta ,   R   ,  Theta ,  V  ,  I ]

data = smrun_new(smscan, "vector_scan");
```

### Advanced: Nested Scanning

```matlab
% 2D scan: Voltage vs Frequency
smscan.loops(1).setchan = "k2400.V_source";  % Inner loop: voltage
smscan.loops(1).rng = [0, 1];
smscan.loops(1).npoints = 51;

smscan.loops(2).setchan = "sr830.frequency";  % Outer loop: frequency  
smscan.loops(2).rng = [100, 1000];
smscan.loops(2).npoints = 21;

smscan.loops(1).getchan = {"sr830.X", "k2400.I_measure"};

% This creates a 51×21 = 1071 point measurement
data = smrun_new(smscan, "voltage_freq_map");
```

## ⚡ PERFORMANCE TIPS

### Measurement Optimization:
- **Single measurements**: Use `smget("channel")` for quick interactive access
- **Batch measurements**: Use `smget({"ch1", "ch2", "ch3"})` for multiple channels
- **Scanning**: Always use `smrun_new()` (10-15% faster than legacy)
- **Batch operations**: Let instrumentRack handle getWrite/getRead separation
- **Direct access**: Use `instrument.getChannel()` for single instrument operations

### Instrument Configuration:
- **Timeouts**: Set appropriate values for slow instruments (default: 5s)
- **Settling times**: Use `waittime` parameter for proper instrument settling  
- **Tolerances**: Define `setTolerances` for critical settable channels
- **Communication**: Use VISA over TCP for remote instruments when possible

### Scan Optimization:
- **Point density**: Start with 101 points (GUI default), adjust as needed
- **Save frequency**: Use `saveloop = 2` (every other point) for long scans
- **Display updates**: Monitor figure 1000 for real-time progress
- **Memory usage**: Consider data size for very large 2D/3D scans

### Common Performance Pitfalls:
- ❌ **Don't**: Create instruments inside scan loops
- ❌ **Don't**: Use legacy `smrun.m` for new measurements  
- ❌ **Don't**: Set very short waittime for slow instruments
- ✅ **Do**: Pre-configure instruments before scanning
- ✅ **Do**: Use appropriate tolerances for verification
- ✅ **Do**: Monitor scan progress via real-time plots

## 🔧 TROUBLESHOOTING

### Connection Issues:
1. **Verify instrument address**: Check GPIB/USB/Ethernet connection
2. **Test basic communication**: Try simple `*IDN?` query
3. **Check VISA drivers**: Ensure proper drivers installed
4. **Timeout errors**: Increase timeout for slow instruments

### Scan Problems:
- **"Channel not found"**: Verify exact channel name spelling
- **Scan won't start**: Check that all setchan/getchan are valid
- **Data missing**: Ensure instruments are properly initialized
- **Plots not updating**: Check that figure 1000 is not manually closed

### Instrument-Specific:
- **SR860 timeouts**: Use `robustReadDouble()` method (auto-retry logic)
- **PowerPoint saves fail**: Ensure Office installed and text_data structure correct
- **Temporary files accumulate**: Check for proper scan completion/cleanup

### Data Recovery:
- **Scan interrupted**: Look for `filename-tempN.mat~` files
- **Figure lost**: Use `smplot("filename.mat")` to recreate plots
- **Data corruption**: Check `.mat` file integrity with `load()` command

### Performance Issues:
- **Slow scanning**: Verify getWrite/getRead separation in custom instruments
- **Memory problems**: Reduce point density or use incremental saving
- **GUI unresponsive**: Check for infinite loops in instrument code

### Getting Help:
- Check instrument manual for command syntax
- Review `instrument_demo.m` for implementation examples
- Use MATLAB debugger to step through instrument methods
- Test instruments individually before combining in scans

## 👨‍💻 DEVELOPMENT GUIDELINES

### Creating New Instruments:

```matlab
classdef instrument_MyDevice < instrumentInterface
    methods
        function obj = instrument_MyDevice(address)
            obj@instrumentInterface();
            % Setup VISA connection, add channels, set tolerances
        end
    end
    
    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(obj, channelIndex)
            % Send measurement commands (no reading!)
        end
        
        function getValues = getReadChannelHelper(obj, channelIndex)
            % Read responses only (after getWrite)
        end
    end
end
```

### Best Practices:
- **Channel naming**: Use descriptive names (`"gate_voltage"` not `"ch1"`)
- **Error handling**: Wrap VISA operations in try-catch blocks
- **Tolerances**: Set appropriate `setTolerances` for settable channels
- **Documentation**: Include usage examples and channel descriptions
- **Testing**: Verify getWrite/getRead separation works correctly

### Code Standards:
- Follow MATLAB naming conventions (`camelCase` for methods)
- Use meaningful variable names and comments
- Implement proper resource cleanup in destructors
- Handle edge cases (timeouts, invalid responses, etc.)
- Include comprehensive input validation

### Debugging Tools:
- Use `instrument_demo.m` as template for new instruments
- Test individual methods before integration
- Use MATLAB debugger to step through communications
- Validate with real hardware before committing changes

## 📚 ADDITIONAL RESOURCES

### Documentation Files:
- `code/sm2/instrumentInterface.m` - Complete API reference with detailed examples
- `code/instruments/instrument_demo.m` - Template implementation and best practices
- `demos/demo.m` - Full system usage example with real instruments
- `demos/readme.txt` - Demo-specific instructions and test data info

### Key System Files:
- `code/smbridge/smrun_new.m` - Main scanning function (entry point)
- `code/smbridge/smget.m` - Quick channel reading (convenience wrapper)
- `code/smbridge/smset.m` - Quick channel setting (convenience wrapper)
- `code/smbridge/smget_new.m` - Full-featured channel reading with batch optimization
- `code/smbridge/smset_new.m` - Channel setting with verification
- `code/smbridge/smplot.m` - Plot recreation from saved data files
- `code/sm2/instrumentRack.m` - Instrument management and batch operations

### Migration References:
- Bridge functions maintain compatibility with legacy SM syntax
- Legacy instruments in `code/legacyInstruments/` preserved for reference  
- Working examples: SR830, SR860 (completed migrations)
- Migration checklist provided in "INSTRUMENT MIGRATION STATUS" section

### External Requirements:
- **MATLAB Toolboxes**: Instrument Control Toolbox (required)
- **VISA Runtime**: NI-VISA or equivalent for instrument communication
- **Hardware**: Compatible GPIB/USB/Ethernet interfaces
- **Documentation**: Instrument manuals for command reference
- **Optional**: Microsoft Office for PowerPoint data logging

### Community Resources:
- SM user community: Original Special Measure documentation
- MATLAB File Exchange: Additional instrument drivers
- Instrument vendor websites: Latest driver downloads and manuals

---

📧 **For questions about this system**: Start with the comprehensive documentation 
   in `instrumentInterface.m` and `instrument_demo.m`. The batch optimization 
   concepts (getWrite/getRead separation) are fundamental to achieving optimal 
   performance with this measurement automation system.

**Quick Help**: Run `demo.m` for working examples, check `demos/data/` for sample 
   output files, and use `smplot.m` to understand data structure and visualization.

---

✨ **SM 1.5 Complete Documentation Guide** - Last Updated: 2025-07-19  
   Prepared for optimal Copilot productivity and user experience
