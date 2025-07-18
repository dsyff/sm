%%
clear;
%clear all;
close all;
global instrumentRackGlobal smscan smaux smdata;
path(pathdef);
username=getenv("USERNAME");
addpath(genpath(sprintf("C:\\Users\\%s\\Desktop\\SM1.5", username)));

% Suppress VISA timeout warnings
warning('off', 'instrument:visa:unsuccessfulSetTimeout');

%% Clean up existing instruments to release serial ports
if exist('instrumentRackGlobal', 'var') && ~isempty(instrumentRackGlobal)
    delete(instrumentRackGlobal);
    clear instrumentRackGlobal;
end

%% instrument addresses
LockIn1_GPIB = 7; %sd
LockIn2_GPIB = 8; %vxx
LockIn3_GPIB = 9; %

K2450_A_GPIB = 17; %strain cell outer
K2450_B_GPIB = 18; %strain cell inner
K2450_C_GPIB = 19; %vtg

E4980AL_GPIB = 6; %E4980AL LCR meter for strain controller

Montana2_IP = "136.167.55.165";
Opticool_IP = "127.0.0.1";

%% GPIB Adaptor Indices - change these to match your setup
adaptorIndex = 0;        % Standard instruments
adaptorIndex_strain = 2; % Strain controller instruments

%% instrument usage flags
counter_Use = 1;
clock_Use = 1;

Lockin1_Use = 0;
Lockin2_Use = 0;
Lockin3_Use = 0;

K2450_A_Use = 0;
K2450_B_Use = 0;
K2450_C_Use = 0;

Montana2_Use = 0;
Opticool_Use = 0; %Opticool

strainController_Use = 0;

%% Handle strain controller dependencies
if strainController_Use
    % Strain controller manages K2450 A&B and cryostat internally
    % Force these to be disabled to avoid conflicts
    if K2450_A_Use || K2450_B_Use
        fprintf('Warning: K2450 A&B disabled - managed internally by strain controller.\n');
        K2450_A_Use = 0;
        K2450_B_Use = 0;
    end
    if Montana2_Use || Opticool_Use
        fprintf('Warning: Cryostat disabled - managed internally by strain controller.\n');
        Montana2_Use = 0;
        Opticool_Use = 0;
    end
end

%% Create instrumentRack
rack = instrumentRack(false); % TF to skip safety dialog for setup script

%% Create strain controller first (if enabled) - manages K2450s A&B and cryostat internally
if strainController_Use
    % Determine cryostat type (default to Montana2)
    cryostat_type = "Montana2"; % Default - change to "Opticool" if needed
    
    handle_strainController = instrument_strainController(...
        address_E4980AL = gpibAddress(E4980AL_GPIB, adaptorIndex_strain), ...
        address_K2450_A = gpibAddress(K2450_A_GPIB, adaptorIndex_strain), ...
        address_K2450_B = gpibAddress(K2450_B_GPIB, adaptorIndex_strain), ...
        address_Montana2 = Montana2_IP, ...
        address_Opticool = Opticool_IP, ...
        cryostat = cryostat_type, ...
        strainCellNumber = 1);
    
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

    % Set initial parameters (based on legacy setup)
    handle_strainController.setParameters(...
        'frequency', 100e3, ...
        'Z_short_r', 1.783, ...
        'Z_short_theta', deg2rad(29.85), ...
        'Z_open_r', 27.9e6, ...
        'Z_open_theta', deg2rad(104.17));
    
    % Perform tare operation
    handle_strainController.tareDisplacement(20);
    
    % Set initial voltages to zero
    smset("strain.V_str_o", 0);
    smset("strain.V_str_i", 0);
    
    fprintf('Strain controller initialized and tared.\n');
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

if K2450_C_Use
    handle_K2450_C = instrument_K2450(gpibAddress(K2450_C_GPIB, adaptorIndex));
    handle_K2450_C.requireSetCheck = false; %dose not wait for instrument to reach set value
    %handle_K2450_C.reset(); % only reset if output ramped to zero
    
    % Configure instrument communication and settings
    h = handle_K2450_C.communicationHandle;
    % Set timeout to 10 seconds to avoid VISA warnings
    try
        h.Timeout = 10;
    catch
        % Ignore if timeout setting fails
    end
    %writeline(h,"source:voltage:read:back off"); %do not measure voltage
    writeline(h,":sense:current:range 1e-7"); %sets the sense current range
    writeline(h,"source:voltage:Ilimit 1e-7"); %sets a current limit protector
    writeline(h,":source:voltage:range 20"); %sets the source voltage range
    %writeline(h,":source:voltage:range:auto ON"); %use auto range for voltage
    %writeline(h,":route:terminals rear"); %use rear terminal
    %writeline(h,":sense:current:NPLcycles 2"); %number of power line cycles per measurement
    writeline(h,":OUTP ON");
    pause(2);
    %andle_K2450_C.chargeCurrentLimit = 1E-7; %used to determine if voltage has been reached on capacitive load
    %handle_K2450_C.setSetTolerances("V_source", 5E-3); %used to determine if voltage has been reached
    
    % Add to rack and configure channels
    rack.addInstrument(handle_K2450_C, "K2450_C");
    rack.addChannel("K2450_C", "V_source", "V_tg", 1, 0.5); % 1V/s ramp rate, 10mV threshold
    rack.addChannel("K2450_C", "I_measure", "I_tg");
    %rack.addChannel("K2450_C", "VI", "VI_tg");
end

if Lockin1_Use
    handle_SR860_1 = instrument_SR860(gpibAddress(LockIn1_GPIB, adaptorIndex));
    handle_SR860_1.requireSetCheck = false;
    
    % Configure instrument (based on legacy setup)
    h = handle_SR860_1.communicationHandle;
    % Uncomment and modify settings as needed:
    %writeline(h, "isrc 0"); % Input source: 0=A, 1=A-B
    %writeline(h, "ivmd 0"); % Input source: 0=voltage, 1=current
    %writeline(h, "ignd 1"); % Input grounding: 0=float, 1=ground
    %writeline(h, "icpl 0"); % Input coupling: 0=AC, 1=DC

    % Add to rack and configure channels
    rack.addInstrument(handle_SR860_1, "LockIn1");
    rack.addChannel("LockIn1", "X", "Ixx_X");
    rack.addChannel("LockIn1", "Theta", "Ixx_Th");
    rack.addChannel("LockIn1", "frequency", "Freq");
    rack.addChannel("LockIn1", "amplitude", "V_exc");
    %rack.addChannel("LockIn1", "Y", "Ixx_Y");
    %rack.addChannel("LockIn1", "R", "Ixx_R");
    %rack.addChannel("LockIn1", "phase", "Ixx_Phase");
    %rack.addChannel("LockIn1", "aux_in_1", "Ixx_AuxIn1");
    %rack.addChannel("LockIn1", "aux_in_2", "Ixx_AuxIn2");
    %rack.addChannel("LockIn1", "aux_in_3", "Ixx_AuxIn3");
    %rack.addChannel("LockIn1", "aux_in_4", "Ixx_AuxIn4");
    %rack.addChannel("LockIn1", "aux_out_1", "Ixx_AuxOut1");
    %rack.addChannel("LockIn1", "aux_out_2", "Ixx_AuxOut2");
    %rack.addChannel("LockIn1", "aux_out_3", "Ixx_AuxOut3");
    %rack.addChannel("LockIn1", "aux_out_4", "Ixx_AuxOut4");
    %rack.addChannel("LockIn1", "sensitivity", "Ixx_Sens");
    %rack.addChannel("LockIn1", "time_constant", "Ixx_TimeConst");
    %rack.addChannel("LockIn1", "sync_filter", "Ixx_SyncFilter");
    %rack.addChannel("LockIn1", "XY", "Ixx_XY");
end

if Lockin2_Use
    handle_SR830_2 = instrument_SR830(gpibAddress(LockIn2_GPIB, adaptorIndex));
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
    rack.addInstrument(handle_SR830_2, "LockIn2");
    rack.addChannel("LockIn2", "X", "Vxx1_X");
    rack.addChannel("LockIn2", "Theta", "Vxx1_Th");
    %rack.addChannel("LockIn2", "Y", "Vxx1_Y");
    %rack.addChannel("LockIn2", "R", "Vxx1_R");
    %rack.addChannel("LockIn2", "frequency", "Vxx1_Freq");
    %rack.addChannel("LockIn2", "amplitude", "Vxx1_Amp");
    %rack.addChannel("LockIn2", "phase", "Vxx1_Phase");
    %rack.addChannel("LockIn2", "aux_in_1", "Vxx1_AuxIn1");
    %rack.addChannel("LockIn2", "aux_in_2", "Vxx1_AuxIn2");
    %rack.addChannel("LockIn2", "aux_in_3", "Vxx1_AuxIn3");
    %rack.addChannel("LockIn2", "aux_in_4", "Vxx1_AuxIn4");
    %rack.addChannel("LockIn2", "aux_out_1", "Vxx1_AuxOut1");
    %rack.addChannel("LockIn2", "aux_out_2", "Vxx1_AuxOut2");
    %rack.addChannel("LockIn2", "aux_out_3", "Vxx1_AuxOut3");
    %rack.addChannel("LockIn2", "aux_out_4", "Vxx1_AuxOut4");
    %rack.addChannel("LockIn2", "sensitivity", "Vxx1_Sens");
    %rack.addChannel("LockIn2", "time_constant", "Vxx1_TimeConst");
    %rack.addChannel("LockIn2", "sync_filter", "Vxx1_SyncFilter");
    %rack.addChannel("LockIn2", "XY", "Vxx1_XY");
end

if Lockin3_Use
    handle_SR830_3 = instrument_SR830(gpibAddress(LockIn3_GPIB, adaptorIndex));
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
    rack.addInstrument(handle_SR830_3, "LockIn3");
    rack.addChannel("LockIn3", "R", "Vxx2_R");
    rack.addChannel("LockIn3", "X", "Vxx2_X");
    rack.addChannel("LockIn3", "Theta", "Vxx2_Th");
    rack.addChannel("LockIn3", "Y", "Vxx2_Y");
    %rack.addChannel("LockIn3", "frequency", "Vxx2_Freq");
    %rack.addChannel("LockIn3", "amplitude", "Vxx2_Amp");
    %rack.addChannel("LockIn3", "phase", "Vxx2_Phase");
    %rack.addChannel("LockIn3", "aux_in_1", "Vxx2_AuxIn1");
    %rack.addChannel("LockIn3", "aux_in_2", "Vxx2_AuxIn2");
    %rack.addChannel("LockIn3", "aux_in_3", "Vxx2_AuxIn3");
    %rack.addChannel("LockIn3", "aux_in_4", "Vxx2_AuxIn4");
    %rack.addChannel("LockIn3", "aux_out_1", "Vxx2_AuxOut1");
    %rack.addChannel("LockIn3", "aux_out_2", "Vxx2_AuxOut2");
    %rack.addChannel("LockIn3", "aux_out_3", "Vxx2_AuxOut3");
    %rack.addChannel("LockIn3", "aux_out_4", "Vxx2_AuxOut4");
    %rack.addChannel("LockIn3", "sensitivity", "Vxx2_Sens");
    %rack.addChannel("LockIn3", "time_constant", "Vxx2_TimeConst");
    %rack.addChannel("LockIn3", "sync_filter", "Vxx2_SyncFilter");
    %rack.addChannel("LockIn3", "XY", "Vxx2_XY");
end

if Montana2_Use
    handle_Montana2 = instrument_Montana2(Montana2_IP);
    handle_Montana2.requireSetCheck = false;
    rack.addInstrument(handle_Montana2, "Montana2");
    rack.addChannel("Montana2", "T", "T");
end

if Opticool_Use
    handle_Opticool = instrument_Opticool(Opticool_IP);
    rack.addInstrument(handle_Opticool, "Opticool");
    rack.addChannel("Opticool", "T", "T");
end

%% wrap up setup
disp(rack)
bridge = smguiBridge(rack);
bridge.initializeSmdata();
% Make rack available globally for the new smset/smget functions
instrumentRackGlobal = rack;

%% start GUI
smgui_small_new();
sm;
