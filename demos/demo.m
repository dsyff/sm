%% initialize
global instrumentRackGlobal smscan smaux smdata bridge tareData;
close all;
% Clean up existing instruments to release serial ports
if exist("instrumentRackGlobal", "var") && ~isempty(instrumentRackGlobal)
    try
        delete(instrumentRackGlobal);
    catch ME
        fprintf("demo deleteInstrumentRackGlobalFailed: %s\n", ME.message);
    end
    clear instrumentRackGlobal;
end

delete(visadevfind);
delete(serialportfind);
clear;
%clear all;
global instrumentRackGlobal smscan smaux smdata bridge tareData;
path(pathdef);
username=getenv("USERNAME");

% Check for sm-main first, then sm-dev, then report error
sm_main_path = sprintf("C:\\Users\\%s\\Desktop\\sm-main", username);
sm_dev_path = sprintf("C:\\Users\\%s\\Desktop\\sm-dev", username);

if exist(sm_main_path, "dir")
    addpath(genpath(sm_main_path));
    fprintf("Added sm-main to path: %s\n", sm_main_path);
elseif exist(sm_dev_path, "dir")
    addpath(genpath(sm_dev_path));
    fprintf("Added sm-dev to path: %s\n", sm_dev_path);
else
    error("Neither sm-main nor sm-dev folders found in %s\\Desktop\\", sprintf("C:\\Users\\%s", username));
end

%% instrument addresses
SR860_1_GPIB = 7; %sd
SR830_1_GPIB = 7; %sd
SR830_2_GPIB = 8; %vxx1
SR830_3_GPIB = 9; %vxx2
SR830_4_GPIB = 10; %vxx3

K2450_A_GPIB = 17; %strain cell outer
K2450_B_GPIB = 18; %strain cell inner
K2450_C_GPIB = 19; 

K2400_A_GPIB = 23; %sd
K2400_B_GPIB = 24; %vtg
K2400_C_GPIB = 19;

E4980AL_GPIB = 6; %E4980AL LCR meter for strain controller

Montana2_IP = "136.167.55.165";
Opticool_IP = "127.0.0.1";

K10CR1_Serial = ""; % Leave blank to use the first detected device

%% GPIB Adaptor Indices - change these to match your setup
% use visadevlist() to find out gpib addresses
adaptorIndex = 0;        % Standard instruments
adaptorIndex_strain = 2; % Strain controller instruments

%% instrument usage flags
counter_Use = 1;
clock_Use = 1;
test_Use = 0; %extra counters for testing
virtual_del_V_Use = 1; % enable virtual V_\delta composite channel example

SR860_1_Use = 0;
SR830_1_Use = 0;
SR830_2_Use = 0;
SR830_3_Use = 0;
SR830_4_Use = 0;

K2450_A_Use = 0;
K2450_B_Use = 0;
K2450_C_Use = 0;

K2400_A_Use = 0;
K2400_B_Use = 0;
K2400_C_Use = 0;

Montana2_Use = 0;
Opticool_Use = 0;

strainController_Use = 0;

K10CR1_Use = 0;
AndorCCD_Use = 0;

%% Handle strain controller dependencies
if strainController_Use
    % Strain controller manages K2450 A&B and cryostat internally
    % Force these to be disabled to avoid conflicts
    if K2450_A_Use || K2450_B_Use
        fprintf("Warning: K2450 A&B disabled - managed internally by strain controller.\n");
        K2450_A_Use = 0;
        K2450_B_Use = 0;
    end
    if Montana2_Use
        fprintf("Warning: Montana2 disabled - managed internally by strain controller.\n");
        Montana2_Use = 0;
    end
end
%% create new parallel pool
if strainController_Use
    currentPool = (gcp('nocreate'));
    if isempty(currentPool) || currentPool.Busy
        delete(currentPool);
        parpool("Processes");
    end
end

%% INSTRUMENT SETUP GUIDE
% This section explains the standard pattern for adding instruments and channels
% to the instrument rack. Follow this pattern for consistent setup.
%
% STEP 1: Create Instrument Object
% ===============================
% Syntax: handle = instrument_ClassName(address)
% Examples:
%   handle_clock = instrument_clock("address_string");
%   handle_K2450 = instrument_K2450(gpibAddress(18, 0));
%   handle_SR830 = instrument_SR830(gpibAddress(7, 0));
%   handle_Montana = instrument_Montana2("192.168.1.100");
%
% STEP 2: Add Instrument to Rack
% ===============================
% Syntax: rack.addInstrument(instrumentHandle, "friendlyName")
% - instrumentHandle: The object created in Step 1
% - friendlyName: A unique string to identify this instrument in the rack
% Examples:
%   rack.addInstrument(handle_clock, "clock");
%   rack.addInstrument(handle_K2450, "K2450_C");
%   rack.addInstrument(handle_SR830, "SR860_1");
%
% STEP 3: Add Channels from Instrument
% ====================================
% Syntax: rack.addChannel("instrumentFriendlyName", "instrumentChannel", "channelFriendlyName", rampRate, rampThreshold)
% - instrumentFriendlyName: Must match the name used in addInstrument
% - instrumentChannel: The actual channel name from the instrument class
% - channelFriendlyName: A unique name for this channel (used in smset/smget)
% - rampRate: (optional) Maximum rate of change (units/second)
% - rampThreshold: (optional) Minimum step size for ramping
% Examples:
%   rack.addChannel("clock", "timeStamp", "time");
%   rack.addChannel("K2450_C", "V_source", "V_tg", 1, 0.5);  % 1V/s rate, 0.5V threshold
%   rack.addChannel("SR860_1", "X", "Ixx_X");
%
% STEP 4: Send Custom Commands to Hardware (Optional)
% ===================================================
% For advanced configuration, you can send custom SCPI/GPIB commands directly to the hardware
% by accessing the instrument's communication handle.
%
% Syntax: h = instrumentHandle.communicationHandle;
% Then use: writeline(h, "command"); or response = writeread(h, "query?");
%
% Examples:
%   % Configure K2450 current measurement settings
%   h = handle_K2450.communicationHandle;
%   writeline(h, ":sense:current:range 1e-7");        % Set current range
%   writeline(h, "source:voltage:Ilimit 1e-7");       % Set current limit
%   writeline(h, ":OUTP ON");                         % Turn output on
%
%   % Configure SR830 lock-in amplifier settings
%   h = handle_SR830.communicationHandle;
%   writeline(h, "isrc 1");                           % Set input to A-B
%   writeline(h, "ignd 1");                           % Set input grounding
%   sensitivity = writeread(h, "sens?");              % Query sensitivity
%
%   % Query instrument identification
%   h = handle_instrument.communicationHandle;
%   id_string = writeread(h, "*IDN?");                % Get instrument ID
%
% IMPORTANT NOTES FOR CUSTOM COMMANDS:
% - Only use this for settings not available through instrument class methods
% - Always check instrument manual for correct SCPI command syntax
% - Use writeline() for commands that don't return data
% - Use writeread() for queries that return responses
% - Be careful with timing - some instruments need delays between commands
% - Custom configuration should be done AFTER adding instrument to rack but BEFORE operation
%
% IMPORTANT NOTES:
% - All names must be unique within their scope (instrument names, channel names)
% - The instrument must be added to rack before adding its channels
% - Channel names from the instrument class can be found in the instrument's documentation
% - Ramping parameters are optional and default to infinite (instant set)
%
% COMMON MISTAKES TO AVOID:
% - Wrong parameter order in addInstrument: use (handle, "name"), not ("name", handle)
% - Mismatched friendly names between addInstrument and addChannel
% - Using non-existent channel names from the instrument class
% - Duplicate friendly names for instruments or channels

%% Create instrumentRack
rack = instrumentRack(false); % TF to skip safety dialog for setup script


%% Create strain controller first (if enabled) - manages K2450s A&B and cryostat internally
if strainController_Use
    cryostat_string = "Opticool"; %Opticool, Montana2
    
    %handle_strainController.plotLastSession();

    handle_strainController = instrument_strainController("strainController_1", ...
        address_E4980AL = gpibAddress(E4980AL_GPIB, adaptorIndex_strain), ...
        address_K2450_A = gpibAddress(K2450_A_GPIB, adaptorIndex_strain), ...
        address_K2450_B = gpibAddress(K2450_B_GPIB, adaptorIndex_strain), ...
        address_Montana2 = Montana2_IP, ...
        address_Opticool = Opticool_IP, ...
        cryostat = cryostat_string, ...
        strainCellNumber = 1);
    
    if exist("tareData", "var") && isempty(tareData)
        tareData = handle_strainController.tare();
    else
        % if crash, load doglog
        handle_strainController.tare(tareData.d_0);
    end

    rack.addInstrument(handle_strainController, "strain");
    rack.addChannel("strain", "del_d", "del_d");
    rack.addChannel("strain", "T", "T");
    rack.addChannel("strain", "Cp", "Cp");
    rack.addChannel("strain", "Q", "Q");
    rack.addChannel("strain", "C", "C");
    rack.addChannel("strain", "d", "d");
    rack.addChannel("strain", "V_str_o", "V_str_o");
    rack.addChannel("strain", "V_str_i", "V_str_i");
    rack.addChannel("strain", "I_str_o", "I_str_o");
    rack.addChannel("strain", "I_str_i", "I_str_i");
    rack.addChannel("strain", "activeControl", "activeControl");

    % Parameters passed via constructor to legacy watchdog. Tare step skipped here; run your
    % preferred tare workflow via the legacy UI/commands if needed.
    
    % Set initial voltages to zero
    % smset("strain.V_str_o", 0);
    % smset("strain.V_str_i", 0);
    
    fprintf("Strain controller rack starts.\n");
    disp(handle_strainController.getRack());
    fprintf("Strain controller rack ends.\n");
    fprintf("Strain controller initialized and tared.\n");
    
end

%% Create other instruments using new sm2
if counter_Use
    handle_counter = instrument_counter("counter");
    handle_counter.requireSetCheck = false;
    rack.addInstrument(handle_counter, "counter");
    rack.addChannel("counter", "count", "count");
end

if clock_Use
    handle_clock = instrument_clock("clock");
    rack.addInstrument(handle_clock, "clock");
    rack.addChannel("clock", "timeStamp", "time");
end

if K2450_A_Use
    handle_K2450_A = instrument_K2450(gpibAddress(K2450_A_GPIB, adaptorIndex));
    handle_K2450_A.requireSetCheck = false; %dose not wait for instrument to reach set value
    %handle_K2450_A.reset(); % only reset if output ramped to zero
    
    % Configure instrument communication and settings
    h = handle_K2450_A.communicationHandle;

    %writeline(h,"source:voltage:read:back off"); %do not measure voltage
    writeline(h,":sense:current:range 1e-7"); %sets the sense current range
    writeline(h,"source:voltage:Ilimit 1e-7"); %sets a current limit protector
    writeline(h,":source:voltage:range 20"); %sets the source voltage range
    %writeline(h,":source:voltage:range:auto ON"); %use auto range for voltage
    %writeline(h,":route:terminals rear"); %use rear terminal
    writeline(h,"NPLcycles 0.2"); %number of power line cycles per measurement
    writeline(h,":OUTP ON");
    pause(2);
    %andle_K2450_A.chargeCurrentLimit = 1E-7; %used to determine if voltage has been reached on capacitive load
    %handle_K2450_A.setSetTolerances("V_source", 5E-3); %used to determine if voltage has been reached
    
    % Add to rack and configure channels
    rack.addInstrument(handle_K2450_A, "K2450_A");
    rack.addChannel("K2450_A", "V_source", "V_tg0", 1, 0.5, -10, 10); % 1V/s ramp rate, 10mV threshold
    rack.addChannel("K2450_A", "I_measure", "I_tg0");
    rack.addChannel("K2450_A", "VI", "VI_tg0");
end

if K2450_B_Use
    handle_K2450_B = instrument_K2450(gpibAddress(K2450_B_GPIB, adaptorIndex));
    handle_K2450_B.requireSetCheck = false; %dose not wait for instrument to reach set value
    %handle_K2450_B.reset(); % only reset if output ramped to zero
    
    % Configure instrument communication and settings
    h = handle_K2450_B.communicationHandle;

    %writeline(h,"source:voltage:read:back off"); %do not measure voltage
    writeline(h,":sense:current:range 1e-7"); %sets the sense current range
    writeline(h,"source:voltage:Ilimit 1e-7"); %sets a current limit protector
    writeline(h,":source:voltage:range 20"); %sets the source voltage range
    %writeline(h,":source:voltage:range:auto ON"); %use auto range for voltage
    %writeline(h,":route:terminals rear"); %use rear terminal
    writeline(h,"NPLcycles 0.2"); %number of power line cycles per measurement
    writeline(h,":OUTP ON");
    pause(2);
    %andle_K2450_B.chargeCurrentLimit = 1E-7; %used to determine if voltage has been reached on capacitive load
    %handle_K2450_B.setSetTolerances("V_source", 5E-3); %used to determine if voltage has been reached
    
    % Add to rack and configure channels
    rack.addInstrument(handle_K2450_B, "K2450_B");
    rack.addChannel("K2450_B", "V_source", "V_tg1", 1, 0.5, -10, 10); % 1V/s ramp rate, 10mV threshold
    rack.addChannel("K2450_B", "I_measure", "I_tg1");
    rack.addChannel("K2450_B", "VI", "VI_tg1");
end

if K2450_C_Use
    handle_K2450_C = instrument_K2450(gpibAddress(K2450_C_GPIB, adaptorIndex));
    handle_K2450_C.requireSetCheck = false; %dose not wait for instrument to reach set value
    %handle_K2450_C.reset(); % only reset if output ramped to zero
    
    % Configure instrument communication and settings
    h = handle_K2450_C.communicationHandle;

    %writeline(h,"source:voltage:read:back off"); %do not measure voltage
    writeline(h,":sense:current:range 1e-7"); %sets the sense current range
    writeline(h,"source:voltage:Ilimit 1e-7"); %sets a current limit protector
    writeline(h,":source:voltage:range 20"); %sets the source voltage range
    %writeline(h,":source:voltage:range:auto ON"); %use auto range for voltage
    %writeline(h,":route:terminals rear"); %use rear terminal
    writeline(h,"NPLcycles 0.2"); %number of power line cycles per measurement
    writeline(h,":OUTP ON");
    pause(2);
    %andle_K2450_C.chargeCurrentLimit = 1E-7; %used to determine if voltage has been reached on capacitive load
    %handle_K2450_C.setSetTolerances("V_source", 5E-3); %used to determine if voltage has been reached
    
    % Add to rack and configure channels
    rack.addInstrument(handle_K2450_C, "K2450_C");
    rack.addChannel("K2450_C", "V_source", "V_tg", 1, 0.5, -10, 10); % 1V/s ramp rate, 10mV threshold
    rack.addChannel("K2450_C", "I_measure", "I_tg");
    rack.addChannel("K2450_C", "VI", "VI_tg");
end

if K2400_A_Use
    handle_K2400_A = instrument_K2400(gpibAddress(K2400_A_GPIB, adaptorIndex));
    handle_K2400_A.requireSetCheck = false; %dose not wait for instrument to reach set value
    %handle_K2400_A.reset(); % only reset if output ramped to zero
    
    % Configure instrument communication and settings
    h = handle_K2400_A.communicationHandle;

    writeline(h,":sense:current:range 1e-7"); %sets the sense current range
    writeline(h,"sense:current:protection 1e-7"); %sets a current limit protector
    writeline(h,":source:voltage:range 20"); %sets the source voltage range
    %writeline(h,":source:voltage:range:auto 1"); %use auto range for voltage
    %writeline(h,":rout:term rear"); %use rear terminal
    writeline(h,":CURRent:NPLCycles 0.2"); %number of power line cycles per measurement
    writeline(h,":output on");
    pause(2);
    %andle_K2400_A.chargeCurrentLimit = 1E-7; %used to determine if voltage has been reached on capacitive load
    %handle_K2400_A.setSetTolerances("V_source", 5E-3); %used to determine if voltage has been reached
    
    % Add to rack and configure channels
    rack.addInstrument(handle_K2400_A, "K2400_A");
    rack.addChannel("K2400_A", "V_source", "V_tg", 1, 1, -10, 10); % 1V/s ramp rate, 1V threshold
    rack.addChannel("K2400_A", "I_measure", "I_tg");
    rack.addChannel("K2400_A", "VI", "VI_sd");
end

if K2400_B_Use
    handle_K2400_B = instrument_K2400(gpibAddress(K2400_B_GPIB, adaptorIndex));
    handle_K2400_B.requireSetCheck = false; %dose not wait for instrument to reach set value
    %handle_K2400_B.reset(); % only reset if output ramped to zero
    
    % Configure instrument communication and settings
    h = handle_K2400_B.communicationHandle;

    writeline(h,":sense:current:range 1e-7"); %sets the sense current range
    writeline(h,"sense:current:protection 1e-7"); %sets a current limit protector
    writeline(h,":source:voltage:range 20"); %sets the source voltage range
    %writeline(h,":source:voltage:range:auto 1"); %use auto range for voltage
    %writeline(h,":rout:term rear"); %use rear terminal
    writeline(h,":CURRent:NPLCycles 0.2"); %number of power line cycles per measurement
    writeline(h,":output on");
    pause(2);
    %andle_K2400_B.chargeCurrentLimit = 1E-7; %used to determine if voltage has been reached on capacitive load
    %handle_K2400_B.setSetTolerances("V_source", 5E-3); %used to determine if voltage has been reached
    
    % Add to rack and configure channels
    rack.addInstrument(handle_K2400_B, "K2400_B");
    rack.addChannel("K2400_B", "V_source", "V_bg", 1, 1, -10, 10); % 1V/s ramp rate, 1V threshold
    rack.addChannel("K2400_B", "I_measure", "I_bg");
    rack.addChannel("K2400_B", "VI", "VI_tg");
end

if K10CR1_Use
    handle_K10CR1 = instrument_K10CR1(K10CR1_Serial);
    rack.addInstrument(handle_K10CR1, "K10CR1");
    rack.addChannel("K10CR1", "position_deg", "K10CR1_position_deg");
end

if AndorCCD_Use
    handle_AndorCCD = instrument_AndorCCD("AndorCCD_demo");
    % check andorHandle.pixelCount for number of pixels
    rack.addInstrument(handle_AndorCCD, "AndorCCD");
    rack.addChannel("AndorCCD", "temperature", "CCD_T"); % cooler temperature in C
    rack.addChannel("AndorCCD", "exposure_time", "CCD_exposure"); % in seconds
    rack.addChannel("AndorCCD", "accumulations", "CCD_accumulations"); % number of accumulations per acquisition
    rack.addChannel("AndorCCD", "pixel_index", "CCD_x_index"); % pixel index for readout
    rack.addChannel("AndorCCD", "counts", "CCD_counts");
end

if K2400_C_Use
    handle_K2400_C = instrument_K2400(gpibAddress(K2400_C_GPIB, adaptorIndex));
    handle_K2400_C.requireSetCheck = false; %dose not wait for instrument to reach set value
    %handle_K2400_C.reset(); % only reset if output ramped to zero
    
    % Configure instrument communication and settings
    h = handle_K2400_C.communicationHandle;

    writeline(h,":sense:current:range 1e-7"); %sets the sense current range
    writeline(h,"sense:current:protection 1e-7"); %sets a current limit protector
    writeline(h,":source:voltage:range 20"); %sets the source voltage range
    %writeline(h,":source:voltage:range:auto 1"); %use auto range for voltage
    %writeline(h,":rout:term rear"); %use rear terminal
    writeline(h,":CURRent:NPLCycles 0.2"); %number of power line cycles per measurement
    writeline(h,":output on");
    pause(2);
    %andle_K2400_C.chargeCurrentLimit = 1E-7; %used to determine if voltage has been reached on capacitive load
    %handle_K2400_C.setSetTolerances("V_source", 5E-3); %used to determine if voltage has been reached
    
    % Add to rack and configure channels
    rack.addInstrument(handle_K2400_C, "K2400_C");
    rack.addChannel("K2400_C", "V_source", "V_tg", 1, 1); % 1V/s ramp rate, 1V threshold
    rack.addChannel("K2400_C", "I_measure", "I_tg");
    rack.addChannel("K2400_C", "VI", "VI_tg");
end

if SR860_1_Use
    handle_SR860_1 = instrument_SR860(gpibAddress(SR860_1_GPIB, adaptorIndex));
    handle_SR860_1.requireSetCheck = false;
    
    % Configure instrument (based on legacy setup)
    h = handle_SR860_1.communicationHandle;
    % Uncomment and modify settings as needed:
    %writeline(h, "isrc 0"); % Input source: 0=A, 1=A-B
    %writeline(h, "ivmd 0"); % Input source: 0=voltage, 1=current
    %writeline(h, "ignd 1"); % Input grounding: 0=float, 1=ground
    %writeline(h, "icpl 0"); % Input coupling: 0=AC, 1=DC

    % Add to rack and configure channels
    rack.addInstrument(handle_SR860_1, "SR860_1");
    %rack.addChannel("SR860_1", "X", "Ixx_X");
    %rack.addChannel("SR860_1", "Theta", "Ixx_Th");
    rack.addChannel("SR860_1", "frequency", "Freq");
    rack.addChannel("SR860_1", "amplitude", "V_exc");
    %rack.addChannel("SR860_1", "Y", "Ixx_Y");
    %rack.addChannel("SR860_1", "R", "Ixx_R");
    %rack.addChannel("SR860_1", "phase", "Ixx_Phase");
    %rack.addChannel("SR860_1", "aux_in_1", "Ixx_AuxIn1");
    %rack.addChannel("SR860_1", "aux_in_2", "Ixx_AuxIn2");
    %rack.addChannel("SR860_1", "aux_in_3", "Ixx_AuxIn3");
    %rack.addChannel("SR860_1", "aux_in_4", "Ixx_AuxIn4");
    %rack.addChannel("SR860_1", "aux_out_1", "Ixx_AuxOut1");
    %rack.addChannel("SR860_1", "aux_out_2", "Ixx_AuxOut2");
    %rack.addChannel("SR860_1", "aux_out_3", "Ixx_AuxOut3");
    %rack.addChannel("SR860_1", "aux_out_4", "Ixx_AuxOut4");
    rack.addChannel("SR860_1", "sensitivity", "Ixx_Sens"); % in volts; multiply by 1E-6 for amps
    %rack.addChannel("SR860_1", "time_constant", "Ixx_TimeConst");
    %rack.addChannel("SR860_1", "sync_filter", "Ixx_SyncFilter");
    %rack.addChannel("SR860_1", "XY", "Ixx_XY");
    rack.addChannel("SR860_1", "XTheta", "Ixx_XTheta");
    %rack.addChannel("SR860_1", "YTheta", "Ixx_YTheta");
    %rack.addChannel("SR860_1", "RTheta", "Ixx_RTheta");
    %rack.addChannel("SR860_1", "dc_offset", "Ixx_dc_offset");
end

if SR830_1_Use
    handle_SR830_1 = instrument_SR830(gpibAddress(SR830_1_GPIB, adaptorIndex));
    handle_SR830_1.requireSetCheck = false;
    
    % Configure instrument (based on legacy setup)
    h = handle_SR830_1.communicationHandle;
    % Uncomment and modify settings as needed:
    %writeline(h, "isrc 0"); % Input source: 0=A, 1=A-B
    %writeline(h, "ivmd 0"); % Input source: 0=voltage, 1=current
    %writeline(h, "ignd 1"); % Input grounding: 0=float, 1=ground
    %writeline(h, "icpl 0"); % Input coupling: 0=AC, 1=DC

    % Add to rack and configure channels
    rack.addInstrument(handle_SR830_1, "SR830_1");
    %rack.addChannel("SR830_1", "X", "Ixx_X");
    %rack.addChannel("SR830_1", "Theta", "Ixx_Th");
    rack.addChannel("SR830_1", "frequency", "Freq");
    rack.addChannel("SR830_1", "amplitude", "V_exc");
    %rack.addChannel("SR830_1", "Y", "Ixx_Y");
    %rack.addChannel("SR830_1", "R", "Ixx_R");
    %rack.addChannel("SR830_1", "phase", "Ixx_Phase");
    %rack.addChannel("SR830_1", "aux_in_1", "Ixx_AuxIn1");
    %rack.addChannel("SR830_1", "aux_in_2", "Ixx_AuxIn2");
    %rack.addChannel("SR830_1", "aux_in_3", "Ixx_AuxIn3");
    %rack.addChannel("SR830_1", "aux_in_4", "Ixx_AuxIn4");
    %rack.addChannel("SR830_1", "aux_out_1", "Ixx_AuxOut1");
    %rack.addChannel("SR830_1", "aux_out_2", "Ixx_AuxOut2");
    %rack.addChannel("SR830_1", "aux_out_3", "Ixx_AuxOut3");
    %rack.addChannel("SR830_1", "aux_out_4", "Ixx_AuxOut4");
    rack.addChannel("SR830_1", "sensitivity", "Ixx_Sens"); % in volts; multiply by 1E-6 for amps
    %rack.addChannel("SR830_1", "time_constant", "Ixx_TimeConst");
    %rack.addChannel("SR830_1", "sync_filter", "Ixx_SyncFilter");
    %rack.addChannel("SR830_1", "XY", "Ixx_XY");
    rack.addChannel("SR830_1", "XTheta", "Ixx_XTheta");
    %rack.addChannel("SR830_1", "YTheta", "Ixx_YTheta");
    %rack.addChannel("SR830_1", "RTheta", "Ixx_RTheta");
    %rack.addChannel("SR830_1", "dc_offset", "Ixx_dc_offset");
end

if SR830_2_Use
    handle_SR830_2 = instrument_SR830(gpibAddress(SR830_2_GPIB, adaptorIndex));
    handle_SR830_2.requireSetCheck = false;
    
    % Configure instrument (based on legacy setup)
    h = handle_SR830_2.communicationHandle;
    writeline(h, "isrc 1"); % sets input to A-B
    % Uncomment and modify additional settings as needed:
    %writeline(h, "ignd 1"); % Input grounding: 0=float, 1=ground
    %writeline(h, "icpl 0"); % Input coupling: 0=AC, 1=DC
    %writeline(h, "ilin 0"); % Input line notch filter: 0=none, 1=line, 2=2xline, 3=both
    %writeline(h, "rmod 0"); % Reserve mode: 0=high, 1=normal, 2=low
    %writeline(h, "slp 0"); % Output filter slope: 0=6dB, 1=12dB, 2=18dB, 3=24dB
    
    % Add to rack and configure channels
    rack.addInstrument(handle_SR830_2, "SR830_2");
    %rack.addChannel("SR830_2", "X", "Vxx1_X");
    %rack.addChannel("SR830_2", "Theta", "Vxx1_Th");
    %rack.addChannel("SR830_2", "Y", "Vxx1_Y");
    %rack.addChannel("SR830_2", "R", "Vxx1_R");
    %rack.addChannel("SR830_2", "frequency", "Vxx1_Freq");
    %rack.addChannel("SR830_2", "amplitude", "Vxx1_Amp");
    %rack.addChannel("SR830_2", "phase", "Vxx1_Phase");
    %rack.addChannel("SR830_2", "aux_in_1", "Vxx1_AuxIn1");
    %rack.addChannel("SR830_2", "aux_in_2", "Vxx1_AuxIn2");
    %rack.addChannel("SR830_2", "aux_in_3", "Vxx1_AuxIn3");
    %rack.addChannel("SR830_2", "aux_in_4", "Vxx1_AuxIn4");
    %rack.addChannel("SR830_2", "aux_out_1", "Vxx1_AuxOut1");
    %rack.addChannel("SR830_2", "aux_out_2", "Vxx1_AuxOut2");
    %rack.addChannel("SR830_2", "aux_out_3", "Vxx1_AuxOut3");
    %rack.addChannel("SR830_2", "aux_out_4", "Vxx1_AuxOut4");
    rack.addChannel("SR830_2", "sensitivity", "Vxx1_Sens"); % in volts; multiply by 1E-6 for amps
    %rack.addChannel("SR830_2", "time_constant", "Vxx1_TimeConst");
    %rack.addChannel("SR830_2", "sync_filter", "Vxx1_SyncFilter");
    %rack.addChannel("SR830_2", "XY", "Vxx1_XY");
    rack.addChannel("SR830_2", "XTheta", "Vxx1_XTheta");
    %rack.addChannel("SR830_2", "YTheta", "Vxx1_YTheta");
    %rack.addChannel("SR830_2", "RTheta", "Vxx1_RTheta");
end

if SR830_3_Use
    handle_SR830_3 = instrument_SR830(gpibAddress(SR830_3_GPIB, adaptorIndex));
    handle_SR830_3.requireSetCheck = false;
    
    % Configure instrument (based on legacy setup)
    h = handle_SR830_3.communicationHandle;
    % Uncomment and modify settings as needed:
    %writeline(h, "isrc 0"); % Input source: 0=A, 1=A-B, 2=I(1MOhm), 3=I(100MOhm)
    %writeline(h, "ignd 1"); % Input grounding: 0=float, 1=ground
    %writeline(h, "icpl 0"); % Input coupling: 0=AC, 1=DC
    %writeline(h, "ilin 0"); % Input line notch filter: 0=none, 1=line, 2=2xline, 3=both
    %writeline(h, "rmod 0"); % Reserve mode: 0=high, 1=normal, 2=low
    %writeline(h, "slp 0"); % Output filter slope: 0=6dB, 1=12dB, 2=18dB, 3=24dB
    
    % Add to rack and configure channels
    rack.addInstrument(handle_SR830_3, "SR830_3");
    %rack.addChannel("SR830_3", "R", "Vxx2_R");
    %rack.addChannel("SR830_3", "X", "Vxx2_X");
    %rack.addChannel("SR830_3", "Theta", "Vxx2_Th");
    %rack.addChannel("SR830_3", "Y", "Vxx2_Y");
    %rack.addChannel("SR830_3", "frequency", "Vxx2_Freq");
    %rack.addChannel("SR830_3", "amplitude", "Vxx2_Amp");
    %rack.addChannel("SR830_3", "phase", "Vxx2_Phase");
    %rack.addChannel("SR830_3", "aux_in_1", "Vxx2_AuxIn1");
    %rack.addChannel("SR830_3", "aux_in_2", "Vxx2_AuxIn2");
    %rack.addChannel("SR830_3", "aux_in_3", "Vxx2_AuxIn3");
    %rack.addChannel("SR830_3", "aux_in_4", "Vxx2_AuxIn4");
    %rack.addChannel("SR830_3", "aux_out_1", "Vxx2_AuxOut1");
    %rack.addChannel("SR830_3", "aux_out_2", "Vxx2_AuxOut2");
    %rack.addChannel("SR830_3", "aux_out_3", "Vxx2_AuxOut3");
    %rack.addChannel("SR830_3", "aux_out_4", "Vxx2_AuxOut4");
    rack.addChannel("SR830_3", "sensitivity", "Vxx2_Sens"); % in volts; multiply by 1E-6 for amps
    %rack.addChannel("SR830_3", "time_constant", "Vxx2_TimeConst");
    %rack.addChannel("SR830_3", "sync_filter", "Vxx2_SyncFilter");
    %rack.addChannel("SR830_3", "XY", "Vxx2_XY");
    rack.addChannel("SR830_3", "XTheta", "Vxx2_XTheta");
    %rack.addChannel("SR830_3", "YTheta", "Vxx2_YTheta");
    %rack.addChannel("SR830_3", "RTheta", "Vxx2_RTheta");
end

if Montana2_Use
    handle_Montana2 = instrument_Montana2(Montana2_IP);
    handle_Montana2.requireSetCheck = true;
    rack.addInstrument(handle_Montana2, "Montana2");
    rack.addChannel("Montana2", "T", "T");
end

if Opticool_Use
    handle_Opticool = instrument_Opticool(Opticool_IP);
    handle_Opticool.requireSetCheck = true;
    rack.addInstrument(handle_Opticool, "Opticool");
    if ~strainController_Use
        rack.addChannel("Opticool", "T", "T");
    end
    rack.addChannel("Opticool", "B", "B");
end

if virtual_del_V_Use
    % Sets V2 according to V2 = V1 + del_V on the master instrument rack provided at construction time.
    handle_virtual_del_V = instrument_virtual_del_V("virtual_delta", rack, ...
        VWSe2ChannelName = "V_WSe2", VTgChannelName = "V_tg");
    rack.addInstrument(handle_virtual_del_V, "virtual_delta");
    rack.addChannel("virtual_delta", "del_V", "del_V", [], [], -10, 10); % No ramp rate, no threshold, limits -10V to +10V
end

%% wrap up setup
%flush all instrument buffers to remove instrument introduction messages
rack.flush();
fprintf("Main rack starts.\n");
disp(rack)
fprintf("Main rack ends.\n");
bridge = smguiBridge(rack);
bridge.initializeSmdata();
% Make rack available globally for the new smset/smget functions
instrumentRackGlobal = rack;

%% start GUI
smgui_small_new();
sm;
