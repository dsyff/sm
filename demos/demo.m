global instrumentRackGlobal smscan smaux smdata bridge tareData; %#ok<NUSED>
%#ok<*GVMIS,*UNRCH>


%% initialize
path(pathdef);
username = getenv("USERNAME");
sm_main_path = sprintf("C:\\Users\\%s\\Desktop\\sm-main", username);
sm_dev_path = sprintf("C:\\Users\\%s\\Desktop\\sm-dev", username);

if exist(sm_dev_path, "dir")
    addpath(genpath(sm_dev_path));
    fprintf("Added sm-dev to path: %s\n", sm_dev_path);
elseif exist(sm_main_path, "dir")
    addpath(genpath(sm_main_path));
    fprintf("Added sm-main to path: %s\n", sm_main_path);
else
    error("demo:MissingCodePath", "Neither sm-dev nor sm-main directories were found on the Desktop.");
end
sminit; % shared setup script keeps demo logic concise


%% instrument addresses
SR860_1_GPIB = 7; %sd
SR830_1_GPIB = 7; %sd
SR830_2_GPIB = 8; %vxx1
SR830_3_GPIB = 9; %vxx2
SR830_4_GPIB = 10; %vxx3

K2450_A_GPIB = 17; %vbg/strain cell outer
K2450_B_GPIB = 18; %vtg/strain cell inner
K2450_C_GPIB = 19; %vtg

K2400_A_GPIB = 23; %vbg
K2400_B_GPIB = 24; %vtg
K2400_C_GPIB = 25; %vtg

E4980AL_GPIB = 6; %E4980AL LCR meter for strain controller

Montana2_IP = "136.167.55.165";
Opticool_IP = "127.0.0.1";
Attodry2100_Address = "192.168.1.1";
MFLI_Address = "dev30037";
SDG2042X_mixed_Address = "USB0::0xF4EC::0xEE38::0123456789::0::INSTR";
SDG2042X_mixed_TARB_Address = SDG2042X_mixed_Address;

K10CR1_Serial = ""; % Leave blank to use the first detected device
BK889B_Serial = "COM3";


%% GPIB Adaptor Indices - change these to match your setup
% use visadevlist() to find out gpib addresses
adaptorIndex = 0;        % Standard instruments
adaptorIndex_strain = 2; % Strain controller instruments


%% instrument usage flags
counter_Use = 1;
clock_Use = 1;
test_Use = 0; %extra counters for testing
virtual_del_V_Use = 0;
virtual_hysteresis_Use = 0;
virtual_nonlinear_T_Use = 0;
virtual_nE_Use = 0;

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
strain_cryostat = "Opticool"; %Opticool, Montana2

K10CR1_Use = 0;
Andor_Use = 0;
Attodry2100_Use = 0;

BK889B_Use = 0;
E4980AL_Use = 0;
MFLI_Use = 0;
SDG2042X_mixed_Use = 0;
SDG2042X_mixed_TARB_Use = 0;


%% Create instrumentRack
rack = instrumentRack(false); % TF to skip safety dialog for setup script


%% Instrument Setup Guide
% -------------------------------------------------------------------------
%
% 1. Add Instrument to Rack:
%    rack.addInstrument(instrumentHandle, "instrumentFriendlyName");
%
% 2. Add Channel to Rack:
%    rack.addChannel("instrumentFriendlyName", "channelName", "channelFriendlyName", ...
%                    rampRate, rampThreshold, softMin, softMax);
%    % Note: rampRate, rampThreshold, softMin, softMax are optional.
%
% For a complete guide and examples, see: demos/INSTRUMENT_SETUP_GUIDE.txt
%
% -------------------------------------------------------------------------

%% Create strain controller first (if enabled) - manages K2450s A&B and cryostat internally
if strainController_Use
    if K2450_A_Use || K2450_B_Use
        fprintf("Warning: K2450 A&B disabled - managed internally by strain controller.\n");
        K2450_A_Use = 0;
        K2450_B_Use = 0;
    end
    if Montana2_Use
        fprintf("Warning: Montana2 disabled - managed internally by strain controller.\n");
        Montana2_Use = 0;
    end

    currentPool = (gcp('nocreate'));
    if isempty(currentPool) || currentPool.Busy
        delete(currentPool);
        parpool("Processes");
    end

    %handle_strainController.plotLastSession();
    if strain_cryostat == "Opticool"
        strainCellNumber_default = 1;
    elseif strain_cryostat == "Montana2"
        strainCellNumber_default = 2;
    else
        error("demo:InvalidStrainCryostat", "strain_cryostat must be either 'Opticool' or 'Montana2'");
    end

    handle_strainController = instrument_strainController("strainController_1", ...
        address_E4980AL = gpibAddress(E4980AL_GPIB, adaptorIndex_strain), ...
        address_K2450_A = gpibAddress(K2450_A_GPIB, adaptorIndex_strain), ...
        address_K2450_B = gpibAddress(K2450_B_GPIB, adaptorIndex_strain), ...
        address_Montana2 = Montana2_IP, ...
        address_Opticool = Opticool_IP, ...
        cryostat = strain_cryostat, ...
        strainCellNumber = strainCellNumber_default);

    if exist("tareData", "var") && isempty(tareData)
        tareData = handle_strainController.tare();
    else
        % if crash, load doglog
        handle_strainController.tare(tareData.d_0);
    end

    rack.addInstrument(handle_strainController, "strain");
    rack.addChannel("strain", "del_d", "del_d", [], [], -5E-5, 5E-5);
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

    fprintf("Strain controller rack starts.\n");
    strainControllerRackSummary = handle_strainController.getRack();
    disp(strainControllerRackSummary);
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
    %handle_K2450_A.chargeCurrentLimit = 1E-7; %used to determine if voltage has been reached on capacitive load
    %handle_K2450_A.setSetTolerances("V_source", 5E-3); %used to determine if voltage has been reached

    % Add to rack and configure channels
    rack.addInstrument(handle_K2450_A, "K2450_A");
    rack.addChannel("K2450_A", "V_source", "V_bg", 1, 0.5, -10, 10); % 1V/s ramp rate, 0.5V threshold
    rack.addChannel("K2450_A", "I_measure", "I_bg");
    rack.addChannel("K2450_A", "VI", "VI_bg");
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
    %handle_K2450_B.chargeCurrentLimit = 1E-7; %used to determine if voltage has been reached on capacitive load
    %handle_K2450_B.setSetTolerances("V_source", 5E-3); %used to determine if voltage has been reached

    % Add to rack and configure channels
    rack.addInstrument(handle_K2450_B, "K2450_B");
    rack.addChannel("K2450_B", "V_source", "V_tg", 1, 0.5, -10, 10); % 1V/s ramp rate, 0.5V threshold
    rack.addChannel("K2450_B", "I_measure", "I_tg");
    rack.addChannel("K2450_B", "VI", "VI_tg");
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
    %handle_K2450_C.chargeCurrentLimit = 1E-7; %used to determine if voltage has been reached on capacitive load
    %handle_K2450_C.setSetTolerances("V_source", 5E-3); %used to determine if voltage has been reached

    % Add to rack and configure channels
    rack.addInstrument(handle_K2450_C, "K2450_C");
    rack.addChannel("K2450_C", "V_source", "V_tg", 1, 0.5, -10, 10); % 1V/s ramp rate, 0.5V threshold
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
    %handle_K2400_A.chargeCurrentLimit = 1E-7; %used to determine if voltage has been reached on capacitive load
    %handle_K2400_A.setSetTolerances("V_source", 5E-3); %used to determine if voltage has been reached

    % Add to rack and configure channels
    rack.addInstrument(handle_K2400_A, "K2400_A");
    rack.addChannel("K2400_A", "V_source", "V_bg", 1, 0.5, -10, 10); % 1V/s ramp rate, 0.5V threshold
    rack.addChannel("K2400_A", "I_measure", "I_bg");
    rack.addChannel("K2400_A", "VI", "VI_bg");
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
    %handle_K2400_B.chargeCurrentLimit = 1E-7; %used to determine if voltage has been reached on capacitive load
    %handle_K2400_B.setSetTolerances("V_source", 5E-3); %used to determine if voltage has been reached

    % Add to rack and configure channels
    rack.addInstrument(handle_K2400_B, "K2400_B");
    rack.addChannel("K2400_B", "V_source", "V_tg", 1, 0.5, -10, 10); % 1V/s ramp rate, 0.5V threshold
    rack.addChannel("K2400_B", "I_measure", "I_tg");
    rack.addChannel("K2400_B", "VI", "VI_tg");
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
    %handle_K2400_C.chargeCurrentLimit = 1E-7; %used to determine if voltage has been reached on capacitive load
    %handle_K2400_C.setSetTolerances("V_source", 5E-3); %used to determine if voltage has been reached

    % Add to rack and configure channels
    rack.addInstrument(handle_K2400_C, "K2400_C");
    rack.addChannel("K2400_C", "V_source", "V_tg", 1, 0.5, -10, 10); % 1V/s ramp rate, 0.5V threshold
    rack.addChannel("K2400_C", "I_measure", "I_tg");
    rack.addChannel("K2400_C", "VI", "VI_tg");
end


if K10CR1_Use
    handle_K10CR1 = instrument_K10CR1(K10CR1_Serial);
    rack.addInstrument(handle_K10CR1, "K10CR1");
    rack.addChannel("K10CR1", "position_deg", "K10CR1_position_deg");
end

if Andor_Use
    handle_AndorSpectrometer = instrument_AndorSpectrometer("AndorSpectrometer");
    handle_AndorSpectrometer.minTimeBetweenAcquisitions_s = 300;
    % check handle_AndorSpectrometer for properties
    rack.batchGetTimeout = minutes(10);
    rack.addInstrument(handle_AndorSpectrometer, "AndorSpectrometer");
    rack.addChannel("AndorSpectrometer", "temperature_C", "CCD_T_C"); % cooler temperature in C
    rack.addChannel("AndorSpectrometer", "exposure_time", "exposure"); % in seconds
    rack.addChannel("AndorSpectrometer", "center_wavelength_nm", "center_wavelength_nm"); % center wavelength in nm
    rack.addChannel("AndorSpectrometer", "grating", "grating"); % spectrograph grating index
    rack.addChannel("AndorSpectrometer", "pixel_index", "pixel_index"); % pixel index for readout
    rack.addChannel("AndorSpectrometer", "wavelength_nm", "wavelength_nm"); % wavelength corresponding to current pixel
    rack.addChannel("AndorSpectrometer", "counts_single", "CCD_counts_1x");
    rack.addChannel("AndorSpectrometer", "counts_double", "CCD_counts_2x");
    rack.addChannel("AndorSpectrometer", "counts_triple", "CCD_counts_3x");
    handle_AndorSpectrometer.currentGratingInfo();
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
    %writeline(h, "isrc 0"); % Input source: 0=A, 1=A-B, 2=I(1MOhm), 3=I(100MOhm)
    %writeline(h, "ignd 1"); % Input grounding: 0=float, 1=ground
    %writeline(h, "icpl 0"); % Input coupling: 0=AC, 1=DC
    %writeline(h, "ilin 0"); % Input line notch filter: 0=none, 1=line, 2=2xline, 3=both
    %writeline(h, "rmod 0"); % Reserve mode: 0=high, 1=normal, 2=low
    %writeline(h, "slp 0"); % Output filter slope: 0=6dB, 1=12dB, 2=18dB, 3=24dB

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
    % Uncomment and modify settings as needed:
    %writeline(h, "isrc 0"); % Input source: 0=A, 1=A-B, 2=I(1MOhm), 3=I(100MOhm)
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

if SR830_4_Use
    handle_SR830_4 = instrument_SR830(gpibAddress(SR830_4_GPIB, adaptorIndex));
    handle_SR830_4.requireSetCheck = false;

    % Configure instrument (based on legacy setup)
    h = handle_SR830_4.communicationHandle;
    % Uncomment and modify settings as needed:
    %writeline(h, "isrc 0"); % Input source: 0=A, 1=A-B, 2=I(1MOhm), 3=I(100MOhm)
    %writeline(h, "ignd 1"); % Input grounding: 0=float, 1=ground
    %writeline(h, "icpl 0"); % Input coupling: 0=AC, 1=DC
    %writeline(h, "ilin 0"); % Input line notch filter: 0=none, 1=line, 2=2xline, 3=both
    %writeline(h, "rmod 0"); % Reserve mode: 0=high, 1=normal, 2=low
    %writeline(h, "slp 0"); % Output filter slope: 0=6dB, 1=12dB, 2=18dB, 3=24dB

    % Add to rack and configure channels
    rack.addInstrument(handle_SR830_4, "SR830_4");
    %rack.addChannel("SR830_4", "R", "Vxx3_R");
    %rack.addChannel("SR830_4", "X", "Vxx3_X");
    %rack.addChannel("SR830_4", "Theta", "Vxx3_Th");
    %rack.addChannel("SR830_4", "Y", "Vxx3_Y");
    %rack.addChannel("SR830_4", "frequency", "Vxx3_Freq");
    %rack.addChannel("SR830_4", "amplitude", "Vxx3_Amp");
    %rack.addChannel("SR830_4", "phase", "Vxx3_Phase");
    %rack.addChannel("SR830_4", "aux_in_1", "Vxx3_AuxIn1");
    %rack.addChannel("SR830_4", "aux_in_2", "Vxx3_AuxIn2");
    %rack.addChannel("SR830_4", "aux_in_3", "Vxx3_AuxIn3");
    %rack.addChannel("SR830_4", "aux_in_4", "Vxx3_AuxIn4");
    %rack.addChannel("SR830_4", "aux_out_1", "Vxx3_AuxOut1");
    %rack.addChannel("SR830_4", "aux_out_2", "Vxx3_AuxOut2");
    %rack.addChannel("SR830_4", "aux_out_3", "Vxx3_AuxOut3");
    %rack.addChannel("SR830_4", "aux_out_4", "Vxx3_AuxOut4");
    rack.addChannel("SR830_4", "sensitivity", "Vxx3_Sens"); % in volts; multiply by 1E-6 for amps
    %rack.addChannel("SR830_4", "time_constant", "Vxx3_TimeConst");
    %rack.addChannel("SR830_4", "sync_filter", "Vxx3_SyncFilter");
    %rack.addChannel("SR830_4", "XY", "Vxx3_XY");
    rack.addChannel("SR830_4", "XTheta", "Vxx3_XTheta");
    %rack.addChannel("SR830_4", "YTheta", "Vxx3_YTheta");
    %rack.addChannel("SR830_4", "RTheta", "Vxx3_RTheta");
end

if MFLI_Use
    handle_MFLI = instrument_MFLI(MFLI_Address);
    rack.addInstrument(handle_MFLI, "MFLI");
    % Add channels for MFLI (4 sine generators)
    for i = 1:4
        rack.addChannel("MFLI", sprintf("Amplitude_%d", i), sprintf("MFLI_Amp_%d", i), [], [], -2, 2);
        rack.addChannel("MFLI", sprintf("Phase_%d", i), sprintf("MFLI_Phase_%d", i)); %degrees
        rack.addChannel("MFLI", sprintf("Frequency_%d", i), sprintf("MFLI_Freq_%d", i));
        rack.addChannel("MFLI", sprintf("Harmonic_%d", i), sprintf("MFLI_Harm_%d", i));
        rack.addChannel("MFLI", sprintf("On_%d", i), sprintf("MFLI_On_%d", i));
    end
end

if SDG2042X_mixed_Use
    % SDG2042X mixed multi-tone output (uploads on every set)
    handle_SDG2042X_mixed = instrument_SDG2042X_mixed(SDG2042X_mixed_Address);
    handle_SDG2042X_mixed.requireSetCheck = false;

    rack.addInstrument(handle_SDG2042X_mixed, "SDG2042X_mixed");
    for i = 1:7
        rack.addChannel("SDG2042X_mixed", string(sprintf("Amplitude_%d", i)), string(sprintf("SDG_Amp_%d", i)));
        rack.addChannel("SDG2042X_mixed", string(sprintf("Phase_%d", i)), string(sprintf("SDG_Phase_%d", i)));
        rack.addChannel("SDG2042X_mixed", string(sprintf("Frequency_%d", i)), string(sprintf("SDG_Freq_%d", i)));
    end
    rack.addChannel("SDG2042X_mixed", "global_phase_offset", "SDG_global_phase_offset");
end

if SDG2042X_mixed_TARB_Use
    % SDG2042X mixed multi-tone output using TrueArb (TARB) mode (uploads on every set)
    handle_SDG2042X_mixed_TARB = instrument_SDG2042X_mixed_TARB(SDG2042X_mixed_TARB_Address, ...
        uploadSampleRateHz = 1e6, ...
        uploadFundamentalFrequencyHz = 1, ...
        roscSource = "INT");
    handle_SDG2042X_mixed_TARB.requireSetCheck = false;

    rack.addInstrument(handle_SDG2042X_mixed_TARB, "SDG2042X_mixed_TARB");
    for i = 1:7
        rack.addChannel("SDG2042X_mixed_TARB", string(sprintf("Amplitude_%d", i)), string(sprintf("SDG_TARB_Amp_%d", i)));
        rack.addChannel("SDG2042X_mixed_TARB", string(sprintf("Phase_%d", i)), string(sprintf("SDG_TARB_Phase_%d", i)));
        rack.addChannel("SDG2042X_mixed_TARB", string(sprintf("Frequency_%d", i)), string(sprintf("SDG_TARB_Freq_%d", i)));
    end
    rack.addChannel("SDG2042X_mixed_TARB", "global_phase_offset", "SDG_TARB_global_phase_offset");
end

if Montana2_Use
    handle_Montana2 = instrument_Montana2(Montana2_IP);
    rack.addInstrument(handle_Montana2, "Montana2");
    rack.addChannel("Montana2", "T", "T");
end

if Opticool_Use
    handle_Opticool = instrument_Opticool(Opticool_IP);
    rack.addInstrument(handle_Opticool, "Opticool");
    if ~strainController_Use
        rack.addChannel("Opticool", "T", "T");
    end
    rack.addChannel("Opticool", "B", "B");
end

if Attodry2100_Use
    handle_attodry2100 = instrument_attodry2100(Attodry2100_Address);
    rack.addInstrument(handle_attodry2100, "Attodry2100");
    rack.addChannel("Attodry2100", "T", "T");
    rack.addChannel("Attodry2100", "B", "B");
end

if BK889B_Use
    handle_BK889B = instrument_BK889B(BK889B_Serial);
    rack.addInstrument(handle_BK889B, "BK889B");
    rack.addChannel("BK889B", "Cp", "BK_Cp");
    rack.addChannel("BK889B", "Q", "BK_Q");
    rack.addChannel("BK889B", "CpQ", "BK_CpQ");
end

if E4980AL_Use
    % Note: E4980AL is typically used with the strain controller, but can be used independently.
    handle_E4980AL = instrument_E4980AL(gpibAddress(E4980AL_GPIB, adaptorIndex_strain));
    rack.addInstrument(handle_E4980AL, "E4980AL");
    rack.addChannel("E4980AL", "Cp", "E4980_Cp");
    rack.addChannel("E4980AL", "Q", "E4980_Q");
    rack.addChannel("E4980AL", "CpQ", "E4980_CpQ");
end

%% Virtual Instruments

if virtual_del_V_Use

    % Sets V_set according to V_set = V_get + del_V on the master instrument rack provided at construction time.
    handle_virtual_del_V = virtualInstrument_del_V("virtual_delta", rack, ...
        vGetChannelName = "V_WSe2", vSetChannelName = "V_tg");
    rack.addInstrument(handle_virtual_del_V, "virtual_delta");
    rack.addChannel("virtual_delta", "del_V", "del_V", [], [], -10, 10); % No ramp rate, no threshold, limits -10V to +10V
end

if virtual_hysteresis_Use
    handle_virtual_hysteresis = virtualInstrument_hysteresis("virtual_hysteresis1", rack, ...
        setChannelName = "V_tg", ...
        min = -5, ...
        max = 5);
    rack.addInstrument(handle_virtual_hysteresis, "virtual_hysteresis1");
    rack.addChannel("virtual_hysteresis1", "hysteresis", "hys_V_tg", [], [], 0, 1);
end

if virtual_nonlinear_T_Use
    handle_virtual_nonlinear_T = virtualInstrument_nonlinear_T("virtual_nonlinear_T", rack, ...
        tSetChannelName = virtual_nonlinear_T_TargetChannel, ...
        tMin = 4, ...
        tMax = 200);
    rack.addInstrument(handle_virtual_nonlinear_T, "virtual_nonlinear_T");
    rack.addChannel("virtual_nonlinear_T", "nonlinear_T", "T_normalized", [], [], 0, 1);
end

if virtual_nE_Use
    handle_virtual_nE = virtualInstrument_nE("virtual_nE", rack, ...
        vTgChannelName = "V_tg", ...
        vBgChannelName = "V_bg", ...
        vTgLimits = [-6, 6], ...
        vBgLimits = [-6, 6], ...
        cnpTg1 = -1, ...
        cnpBg1 = 1, ...
        cnpTg2 = -2, ...
        cnpBg2 = 2);
    rack.addInstrument(handle_virtual_nE, "virtual_nE");
    rack.addChannel("virtual_nE", "n", "n_normalized", [], [], 0, 1);
    rack.addChannel("virtual_nE", "E", "E_normalized", [], [], 0, 1);
end



%% wrap up setup
smready(rack);
