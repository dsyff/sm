global smscan smaux smdata bridge; %#ok<NUSED>
%#ok<*GVMIS,*UNRCH>


%% initialize
path(pathdef);
username = string(getenv("USERNAME"));
sm_main_path = fullfile("C:\Users", username, "Desktop", "sm-main");
sm_dev_path = fullfile("C:\Users", username, "Desktop", "sm-dev");

if exist(sm_dev_path, "dir")
    codePath = fullfile(sm_dev_path, "code");
    addpath(codePath);
    fprintf("Added sm-dev code folder to path: %s\n", codePath);
elseif exist(sm_main_path, "dir")
    codePath = fullfile(sm_main_path, "code");
    addpath(codePath);
    fprintf("Added sm-main code folder to path: %s\n", codePath);
else
    error("demo:MissingCodePath", "Neither sm-dev nor sm-main directories were found on the Desktop.");
end
sminit; % shared setup script keeps demo logic concise


%% instrument addresses
Montana1_IP = "136.167.55.127";
Montana2_IP = "136.167.55.165";
OptiCool_IP = "127.0.0.1";

SR860_1_GPIB = 7; % use same GPIB as SR830_1
SR830_1_GPIB = SR860_1_GPIB; %sd
SR860_2_GPIB = 8; % use same GPIB as SR830_2
SR830_2_GPIB = SR860_2_GPIB; %vxx1
SR860_3_GPIB = 9; % use same GPIB as SR830_3
SR830_3_GPIB = SR860_3_GPIB; %vxx2
SR860_4_GPIB = 10; % use same GPIB as SR830_4
SR830_4_GPIB = SR860_4_GPIB; %vxx3
SR860_5_GPIB = 11; % use same GPIB as SR830_5
SR830_5_GPIB = SR860_5_GPIB; %vxx4

K2450_A_GPIB = 17; %vbg/strain cell outer
K2450_B_GPIB = 18; %vtg/strain cell inner
K2450_C_GPIB = 19; %vtg

K2400_A_GPIB = 23; %vbg
K2400_B_GPIB = 24; %vtg
K2400_C_GPIB = 25; %vtg

HP34401A_A_GPIB = 20; %dmm A
HP34401A_B_GPIB = 21; %dmm B

K10CR1_Serial = ""; % Leave blank to use the first detected device

% Thorlabs CS165MU camera (TLCamera SDK)
CS165MU_Serial = ""; % Leave blank to use the first detected camera

attoDRY2100_Address = "192.168.1.1";
ANC300_Serial = "COM6";

% ST3215-HS bus servos via Waveshare Bus Servo Adapter (A)
ST3215HS_Serial = "COM4";
% Attodry autofocus optics: 3 sets (camera BS + LED BS; red block + red ND; green block + green ND)
ST3215HS_BS_Serial = "COM4";       % camera BS (servo 1), LED BS (servo 2)
ST3215HS_red_Serial = "COM4";     % red block (servo 1), red ND (servo 2)
ST3215HS_green_Serial = "COM4";   % green block (servo 1), green ND (servo 2)

% WS2811 color LED controller (Pico 2 USB CDC)
colorLED_Serial = "COM5";
USB6001_Device = "dev1";
USB6001_numAIChannels = 1;
USB6001_accumulations = 1;
USB6001_samplingRate_Hz = 2E4;

E4980AL_GPIB = 6; %E4980AL LCR meter for strain controller
BK889B_Serial = "COM3";

MFLI_Address = "dev30037";
SDG2042X_mixed_Address = "USB0::0xF4EC::0xEE38::0123456789::0::INSTR";
SDG2042X_pure_Address = "USB0::0xF4EC::0x1102::SDG2XCAD4R3406::0::INSTR";
SDG2042X_mixed_TARB_Address = SDG2042X_mixed_Address;


%% GPIB Adaptor Indices - change these to match your setup
% use visadevlist() to find out gpib addresses
adaptorIndex = 0;        % Standard instruments
adaptorIndex_strain = 2; % Strain controller instruments


%% instrument usage flags
counter_Use = 0;
clock_Use = 0;

strainController_Use = 0;
strain_cryostat = "Montana2"; %OptiCool, Montana2
%strain_outerCurrentLimit = 1.6e-7; % A, K2450_A :SOURce:VOLTage:ILIMit
strain_outerCurrentLimit = 3.2e-7; % A, K2450_A :SOURce:VOLTage:ILIMit
%strain_innerCurrentLimit = 1e-7; % A, K2450_B :SOURce:VOLTage:ILIMit
strain_innerCurrentLimit = 2e-7; % A, K2450_B :SOURce:VOLTage:ILIMit

Montana1_Use = 0;
Montana2_Use = 0;
OptiCool_Use = 0;
attoDRY2100_Use = 0;
ANC300_Use = 0; % nano positioner for attoDRY2100

SR860_1_Use = 0;
SR860_1_keyword = "Ixx";
SR830_1_Use = 0;
SR830_1_keyword = "Ixx";
SR860_2_Use = 0;
SR860_2_keyword = "Vxx1";
SR830_2_Use = 0;
SR830_2_keyword = "Vxx1";
SR860_3_Use = 0;
SR860_3_keyword = "Vxx2";
SR830_3_Use = 0;
SR830_3_keyword = "Vxx2";
SR860_4_Use = 0;
SR860_4_keyword = "Vxx3";
SR830_4_Use = 0;
SR830_4_keyword = "Vxx3";
SR860_5_Use = 0;
SR860_5_keyword = "Vxx4";
SR830_5_Use = 0;
SR830_5_keyword = "Vxx4";

K2450_A_Use = 0;
K2450_A_keyword = "bg";
K2450_B_Use = 0;
K2450_B_keyword = "tg";
K2450_C_Use = 0;
K2450_C_keyword = "tg";

K2400_A_Use = 0;
K2400_A_keyword = "bg";
K2400_B_Use = 0;
K2400_B_keyword = "tg";
K2400_C_Use = 0;
K2400_C_keyword = "tg";

HP34401A_A_Use = 0;
HP34401A_B_Use = 0;

K10CR1_Use = 0;
CS165MU_Use = 0;
Andor_Use = 0;
ST3215HS_Use = 0;
ST3215HS_BS_Use = 0;
ST3215HS_red_Use = 0;
ST3215HS_green_Use = 0;
colorLED_Use = 0;
USB6001_Use = 0;
virtual_attodryAutofocus_Use = 0;

E4980AL_Use = 0;
BK889B_Use = 0;

MFLI_Use = 0;
SDG2042X_mixed_Use = 0;
SDG2042X_pure_Use = 0;
SDG2042X_mixed_TARB_Use = 0;

virtual_del_V_Use = 0;
virtual_hysteresis_Use = 0;
virtual_nonlinear_T_Use = 0;
virtual_nE_Use = 0;

%% Create instrumentRackRecipe
recipe = instrumentRackRecipe();
recipe.slack_notification_account_email = "";

% Recipe calling syntax (quick reference):
% recipe.addInstrument("handleVar", "instrument_ClassName", "friendlyName", constructorArgs..., nameValueArgs...);
% recipe.addVirtualInstrument("handleVar", "virtualInstrument_ClassName", "friendlyName", constructorArgs..., nameValueArgs...);
% recipe.addStatement("instrumentFriendlyName", "worker-side MATLAB code string");
% recipe.addChannel("instrumentFriendlyName", "channel", "channelFriendlyName", rampRate, rampThreshold, softwareMin, softwareMax);

%% create instruments
if counter_Use
    recipe.addInstrument("handle_counter", "instrument_counter", "counter", "counter");
    recipe.addStatement("counter", "handle_counter.requireSetCheck = false;");
    recipe.addChannel("counter", "count", "count");
end

if clock_Use
    recipe.addInstrument("handle_clock", "instrument_clock", "clock", "clock");
    recipe.addChannel("clock", "timeStamp", "time");
end

if strainController_Use
    if strain_cryostat == "OptiCool"
        strainCellNumber_default = 1;
    elseif strain_cryostat == "Montana2"
        strainCellNumber_default = 2;
    else
        error("demo:InvalidStrainCryostat", "strain_cryostat must be either 'OptiCool' or 'Montana2'");
    end

    recipe.addInstrument("handle_strainController", "instrument_strainController", "strain", "strainController_1", ...
        address_E4980AL = gpibAddress(E4980AL_GPIB, adaptorIndex_strain), ...
        address_K2450_A = gpibAddress(K2450_A_GPIB, adaptorIndex_strain), ...
        address_K2450_B = gpibAddress(K2450_B_GPIB, adaptorIndex_strain), ...
        address_Montana2 = Montana2_IP, ...
        address_OptiCool = OptiCool_IP, ...
        cryostat = strain_cryostat, ...
        strainCellNumber = strainCellNumber_default, ...
        outerCurrentLimit = strain_outerCurrentLimit, ...
        innerCurrentLimit = strain_innerCurrentLimit, ...
        numeWorkersRequested = 1);

    % Strain controller constructor restores tareData from logs (or tares if missing).

    recipe.addChannel("strain", "del_d", "del_d", [], [], -5E-5, 5E-5);
    recipe.addChannel("strain", "T", "T");
    recipe.addChannel("strain", "Cp", "Cp");
    recipe.addChannel("strain", "Q", "Q");
    recipe.addChannel("strain", "C", "C");
    recipe.addChannel("strain", "d", "d");
    recipe.addChannel("strain", "V_str_o", "V_str_o");
    recipe.addChannel("strain", "V_str_i", "V_str_i");
    recipe.addChannel("strain", "I_str_o", "I_str_o");
    recipe.addChannel("strain", "I_str_i", "I_str_i");
    recipe.addChannel("strain", "activeControl", "activeControl");

    % use instrument_strainController.plotLastSession() to view last
    % active control session

end

if Montana1_Use
    recipe.addInstrument("handle_Montana1", "instrument_Montana1", "Montana1", Montana1_IP);
    recipe.addChannel("Montana1", "T", "T");
end

if Montana2_Use && ~strainController_Use
    recipe.addInstrument("handle_Montana2", "instrument_Montana2", "Montana2", Montana2_IP);
    recipe.addChannel("Montana2", "T", "T");
end

if OptiCool_Use
    recipe.addInstrument("handle_OptiCool", "instrument_OptiCool", "OptiCool", OptiCool_IP);
    if ~strainController_Use
        recipe.addChannel("OptiCool", "T", "T");
    end
    recipe.addChannel("OptiCool", "B", "B");
end

if SR860_1_Use
    recipe.addInstrument("handle_SR860_1", "instrument_SR860", "SR860_1", gpibAddress(SR860_1_GPIB, adaptorIndex));
    recipe.addStatement("SR860_1", "handle_SR860_1.requireSetCheck = false;");
    % Optional SR860 frontend settings (commented by default):
    % recipe.addStatement("SR860_1", "h = handle_SR860_1.communicationHandle;");
    % recipe.addStatement("SR860_1", "writeline(h, ""isrc 1"");"); % Input source: 0=A, 1=A-B
    % recipe.addStatement("SR860_1", "writeline(h, ""ivmd 0"");"); % Input source: 0=voltage, 1=current
    % recipe.addStatement("SR860_1", "writeline(h, ""ignd 1"");"); % Input grounding: 0=float, 1=ground
    % recipe.addStatement("SR860_1", "writeline(h, ""icpl 0"");"); % Input coupling: 0=AC, 1=DC
    % Optional SR860 channels (commented by default):
    % recipe.addChannel("SR860_1", "X", SR860_1_keyword + "_X");
    % recipe.addChannel("SR860_1", "Y", SR860_1_keyword + "_Y");
    % recipe.addChannel("SR860_1", "R", SR860_1_keyword + "_R");
    % recipe.addChannel("SR860_1", "Theta", SR860_1_keyword + "_Theta");
    recipe.addChannel("SR860_1", "frequency", SR860_1_keyword + "_Freq");
    recipe.addChannel("SR860_1", "amplitude", SR860_1_keyword + "_V_exc");
    % recipe.addChannel("SR860_1", "aux_in_0", "SR860_aux_in_0");
    % recipe.addChannel("SR860_1", "aux_in_1", "SR860_aux_in_1");
    % recipe.addChannel("SR860_1", "aux_in_2", "SR860_aux_in_2");
    % recipe.addChannel("SR860_1", "aux_in_3", "SR860_aux_in_3");
    % recipe.addChannel("SR860_1", "aux_out_0", "SR860_aux_out_0");
    % recipe.addChannel("SR860_1", "aux_out_1", "SR860_aux_out_1");
    % recipe.addChannel("SR860_1", "aux_out_2", "SR860_aux_out_2");
    % recipe.addChannel("SR860_1", "aux_out_3", "SR860_aux_out_3");
    recipe.addChannel("SR860_1", "sensitivity", SR860_1_keyword + "_Sens");
    % recipe.addChannel("SR860_1", "time_constant", SR860_1_keyword + "_tau");
    % recipe.addChannel("SR860_1", "sync_filter", SR860_1_keyword + "_sync");
    % recipe.addChannel("SR860_1", "XY", SR860_1_keyword + "_XY");
    recipe.addChannel("SR860_1", "XTheta", SR860_1_keyword + "_XTheta");
    % recipe.addChannel("SR860_1", "YTheta", SR860_1_keyword + "_YTheta");
    % recipe.addChannel("SR860_1", "RTheta", SR860_1_keyword + "_RTheta");
    % recipe.addChannel("SR860_1", "dc_offset", SR860_1_keyword + "_dc_offset");
end

if SR830_1_Use
    recipe.addInstrument("handle_SR830_1", "instrument_SR830", "SR830_1", gpibAddress(SR830_1_GPIB, adaptorIndex));
    recipe.addStatement("SR830_1", "handle_SR830_1.requireSetCheck = false;");
    % Optional SR830 frontend settings (commented by default):
    % recipe.addStatement("SR830_1", "h = handle_SR830_1.communicationHandle;");
    % recipe.addStatement("SR830_1", "writeline(h, ""isrc 1"");"); % Input source: 0=A, 1=A-B, 2=I(1MOhm), 3=I(100MOhm)
    % recipe.addStatement("SR830_1", "writeline(h, ""ignd 1"");"); % Input grounding: 0=float, 1=ground
    % recipe.addStatement("SR830_1", "writeline(h, ""icpl 0"");"); % Input coupling: 0=AC, 1=DC
    % recipe.addStatement("SR830_1", "writeline(h, ""ilin 0"");"); % Input line notch filter: 0=none, 1=line, 2=2xline, 3=both
    % recipe.addStatement("SR830_1", "writeline(h, ""rmod 0"");"); % Reserve mode: 0=high, 1=normal, 2=low
    % recipe.addStatement("SR830_1", "writeline(h, ""slp 0"");"); % Output filter slope: 0=6dB, 1=12dB, 2=18dB, 3=24dB
    % Optional SR830 channels (commented by default):
    % recipe.addChannel("SR830_1", "X", SR830_1_keyword + "_X");
    % recipe.addChannel("SR830_1", "Y", SR830_1_keyword + "_Y");
    % recipe.addChannel("SR830_1", "R", SR830_1_keyword + "_R");
    % recipe.addChannel("SR830_1", "Theta", SR830_1_keyword + "_Theta");
    recipe.addChannel("SR830_1", "frequency", SR830_1_keyword + "_Freq");
    recipe.addChannel("SR830_1", "amplitude", SR830_1_keyword + "_V_exc");
    % recipe.addChannel("SR830_1", "aux_in_1", "SR830_1_aux_in_1");
    % recipe.addChannel("SR830_1", "aux_in_2", "SR830_1_aux_in_2");
    % recipe.addChannel("SR830_1", "aux_in_3", "SR830_1_aux_in_3");
    % recipe.addChannel("SR830_1", "aux_in_4", "SR830_1_aux_in_4");
    % recipe.addChannel("SR830_1", "aux_out_1", "SR830_1_aux_out_1");
    % recipe.addChannel("SR830_1", "aux_out_2", "SR830_1_aux_out_2");
    % recipe.addChannel("SR830_1", "aux_out_3", "SR830_1_aux_out_3");
    % recipe.addChannel("SR830_1", "aux_out_4", "SR830_1_aux_out_4");
    recipe.addChannel("SR830_1", "sensitivity", SR830_1_keyword + "_Sens");
    % recipe.addChannel("SR830_1", "time_constant", SR830_1_keyword + "_tau");
    % recipe.addChannel("SR830_1", "sync_filter", SR830_1_keyword + "_sync");
    % recipe.addChannel("SR830_1", "XY", SR830_1_keyword + "_XY");
    recipe.addChannel("SR830_1", "XTheta", SR830_1_keyword + "_XTheta");
    % recipe.addChannel("SR830_1", "YTheta", SR830_1_keyword + "_YTheta");
    % recipe.addChannel("SR830_1", "RTheta", SR830_1_keyword + "_RTheta");
end

if SR860_2_Use
    recipe.addInstrument("handle_SR860_2", "instrument_SR860", "SR860_2", gpibAddress(SR860_2_GPIB, adaptorIndex));
    recipe.addStatement("SR860_2", "handle_SR860_2.requireSetCheck = false;");
    % Optional SR860 frontend settings (commented by default):
    % recipe.addStatement("SR860_2", "h = handle_SR860_2.communicationHandle;");
    % recipe.addStatement("SR860_2", "writeline(h, ""isrc 1"");"); % Input source: 0=A, 1=A-B
    % recipe.addStatement("SR860_2", "writeline(h, ""ivmd 0"");"); % Input source: 0=voltage, 1=current
    % recipe.addStatement("SR860_2", "writeline(h, ""ignd 1"");"); % Input grounding: 0=float, 1=ground
    % recipe.addStatement("SR860_2", "writeline(h, ""icpl 0"");"); % Input coupling: 0=AC, 1=DC
    % Optional SR860 channels (commented by default):
    % recipe.addChannel("SR860_2", "X", SR860_2_keyword + "_X");
    % recipe.addChannel("SR860_2", "Y", SR860_2_keyword + "_Y");
    % recipe.addChannel("SR860_2", "R", SR860_2_keyword + "_R");
    % recipe.addChannel("SR860_2", "Theta", SR860_2_keyword + "_Theta");
    % recipe.addChannel("SR860_2", "frequency", SR860_2_keyword + "_Freq");
    % recipe.addChannel("SR860_2", "amplitude", SR860_2_keyword + "_V_exc");
    % recipe.addChannel("SR860_2", "aux_in_0", "SR860_2_aux_in_0");
    % recipe.addChannel("SR860_2", "aux_in_1", "SR860_2_aux_in_1");
    % recipe.addChannel("SR860_2", "aux_in_2", "SR860_2_aux_in_2");
    % recipe.addChannel("SR860_2", "aux_in_3", "SR860_2_aux_in_3");
    % recipe.addChannel("SR860_2", "aux_out_0", "SR860_2_aux_out_0");
    % recipe.addChannel("SR860_2", "aux_out_1", "SR860_2_aux_out_1");
    % recipe.addChannel("SR860_2", "aux_out_2", "SR860_2_aux_out_2");
    % recipe.addChannel("SR860_2", "aux_out_3", "SR860_2_aux_out_3");
    recipe.addChannel("SR860_2", "sensitivity", SR860_2_keyword + "_Sens");
    % recipe.addChannel("SR860_2", "time_constant", SR860_2_keyword + "_tau");
    % recipe.addChannel("SR860_2", "sync_filter", SR860_2_keyword + "_sync");
    % recipe.addChannel("SR860_2", "XY", SR860_2_keyword + "_XY");
    recipe.addChannel("SR860_2", "XTheta", SR860_2_keyword + "_XTheta");
    % recipe.addChannel("SR860_2", "YTheta", SR860_2_keyword + "_YTheta");
    % recipe.addChannel("SR860_2", "RTheta", SR860_2_keyword + "_RTheta");
    % recipe.addChannel("SR860_2", "dc_offset", SR860_2_keyword + "_dc_offset");
end

if SR830_2_Use
    recipe.addInstrument("handle_SR830_2", "instrument_SR830", "SR830_2", gpibAddress(SR830_2_GPIB, adaptorIndex));
    recipe.addStatement("SR830_2", "handle_SR830_2.requireSetCheck = false;");
    % Optional SR830 frontend settings (commented by default):
    % recipe.addStatement("SR830_2", "h = handle_SR830_2.communicationHandle;");
    % recipe.addStatement("SR830_2", "writeline(h, ""isrc 1"");"); % Input source: 0=A, 1=A-B, 2=I(1MOhm), 3=I(100MOhm)
    % recipe.addStatement("SR830_2", "writeline(h, ""ignd 1"");"); % Input grounding: 0=float, 1=ground
    % recipe.addStatement("SR830_2", "writeline(h, ""icpl 0"");"); % Input coupling: 0=AC, 1=DC
    % recipe.addStatement("SR830_2", "writeline(h, ""ilin 0"");"); % Input line notch filter: 0=none, 1=line, 2=2xline, 3=both
    % recipe.addStatement("SR830_2", "writeline(h, ""rmod 0"");"); % Reserve mode: 0=high, 1=normal, 2=low
    % recipe.addStatement("SR830_2", "writeline(h, ""slp 0"");"); % Output filter slope: 0=6dB, 1=12dB, 2=18dB, 3=24dB
    % Optional SR830 channels (commented by default):
    % recipe.addChannel("SR830_2", "X", SR830_2_keyword + "_X");
    % recipe.addChannel("SR830_2", "Y", SR830_2_keyword + "_Y");
    % recipe.addChannel("SR830_2", "R", SR830_2_keyword + "_R");
    % recipe.addChannel("SR830_2", "Theta", SR830_2_keyword + "_Theta");
    % recipe.addChannel("SR830_2", "frequency", SR830_2_keyword + "_Freq");
    % recipe.addChannel("SR830_2", "amplitude", SR830_2_keyword + "_V_exc");
    % recipe.addChannel("SR830_2", "aux_in_1", "SR830_2_aux_in_1");
    % recipe.addChannel("SR830_2", "aux_in_2", "SR830_2_aux_in_2");
    % recipe.addChannel("SR830_2", "aux_in_3", "SR830_2_aux_in_3");
    % recipe.addChannel("SR830_2", "aux_in_4", "SR830_2_aux_in_4");
    % recipe.addChannel("SR830_2", "aux_out_1", "SR830_2_aux_out_1");
    % recipe.addChannel("SR830_2", "aux_out_2", "SR830_2_aux_out_2");
    % recipe.addChannel("SR830_2", "aux_out_3", "SR830_2_aux_out_3");
    % recipe.addChannel("SR830_2", "aux_out_4", "SR830_2_aux_out_4");
    recipe.addChannel("SR830_2", "sensitivity", SR830_2_keyword + "_Sens");
    % recipe.addChannel("SR830_2", "time_constant", SR830_2_keyword + "_tau");
    % recipe.addChannel("SR830_2", "sync_filter", SR830_2_keyword + "_sync");
    % recipe.addChannel("SR830_2", "XY", SR830_2_keyword + "_XY");
    recipe.addChannel("SR830_2", "XTheta", SR830_2_keyword + "_XTheta");
    % recipe.addChannel("SR830_2", "YTheta", SR830_2_keyword + "_YTheta");
    % recipe.addChannel("SR830_2", "RTheta", SR830_2_keyword + "_RTheta");
end

if SR860_3_Use
    recipe.addInstrument("handle_SR860_3", "instrument_SR860", "SR860_3", gpibAddress(SR860_3_GPIB, adaptorIndex));
    recipe.addStatement("SR860_3", "handle_SR860_3.requireSetCheck = false;");
    % Optional SR860 frontend settings (commented by default):
    % recipe.addStatement("SR860_3", "h = handle_SR860_3.communicationHandle;");
    % recipe.addStatement("SR860_3", "writeline(h, ""isrc 1"");"); % Input source: 0=A, 1=A-B
    % recipe.addStatement("SR860_3", "writeline(h, ""ivmd 0"");"); % Input source: 0=voltage, 1=current
    % recipe.addStatement("SR860_3", "writeline(h, ""ignd 1"");"); % Input grounding: 0=float, 1=ground
    % recipe.addStatement("SR860_3", "writeline(h, ""icpl 0"");"); % Input coupling: 0=AC, 1=DC
    % Optional SR860 channels (commented by default):
    % recipe.addChannel("SR860_3", "X", SR860_3_keyword + "_X");
    % recipe.addChannel("SR860_3", "Y", SR860_3_keyword + "_Y");
    % recipe.addChannel("SR860_3", "R", SR860_3_keyword + "_R");
    % recipe.addChannel("SR860_3", "Theta", SR860_3_keyword + "_Theta");
    % recipe.addChannel("SR860_3", "frequency", SR860_3_keyword + "_Freq");
    % recipe.addChannel("SR860_3", "amplitude", SR860_3_keyword + "_V_exc");
    % recipe.addChannel("SR860_3", "aux_in_0", "SR860_3_aux_in_0");
    % recipe.addChannel("SR860_3", "aux_in_1", "SR860_3_aux_in_1");
    % recipe.addChannel("SR860_3", "aux_in_2", "SR860_3_aux_in_2");
    % recipe.addChannel("SR860_3", "aux_in_3", "SR860_3_aux_in_3");
    % recipe.addChannel("SR860_3", "aux_out_0", "SR860_3_aux_out_0");
    % recipe.addChannel("SR860_3", "aux_out_1", "SR860_3_aux_out_1");
    % recipe.addChannel("SR860_3", "aux_out_2", "SR860_3_aux_out_2");
    % recipe.addChannel("SR860_3", "aux_out_3", "SR860_3_aux_out_3");
    recipe.addChannel("SR860_3", "sensitivity", SR860_3_keyword + "_Sens");
    % recipe.addChannel("SR860_3", "time_constant", SR860_3_keyword + "_tau");
    % recipe.addChannel("SR860_3", "sync_filter", SR860_3_keyword + "_sync");
    % recipe.addChannel("SR860_3", "XY", SR860_3_keyword + "_XY");
    recipe.addChannel("SR860_3", "XTheta", SR860_3_keyword + "_XTheta");
    % recipe.addChannel("SR860_3", "YTheta", SR860_3_keyword + "_YTheta");
    % recipe.addChannel("SR860_3", "RTheta", SR860_3_keyword + "_RTheta");
    % recipe.addChannel("SR860_3", "dc_offset", SR860_3_keyword + "_dc_offset");
end

if SR830_3_Use
    recipe.addInstrument("handle_SR830_3", "instrument_SR830", "SR830_3", gpibAddress(SR830_3_GPIB, adaptorIndex));
    recipe.addStatement("SR830_3", "handle_SR830_3.requireSetCheck = false;");
    % Optional SR830 frontend settings (commented by default):
    % recipe.addStatement("SR830_3", "h = handle_SR830_3.communicationHandle;");
    % recipe.addStatement("SR830_3", "writeline(h, ""isrc 1"");"); % Input source: 0=A, 1=A-B, 2=I(1MOhm), 3=I(100MOhm)
    % recipe.addStatement("SR830_3", "writeline(h, ""ignd 1"");"); % Input grounding: 0=float, 1=ground
    % recipe.addStatement("SR830_3", "writeline(h, ""icpl 0"");"); % Input coupling: 0=AC, 1=DC
    % recipe.addStatement("SR830_3", "writeline(h, ""ilin 0"");"); % Input line notch filter: 0=none, 1=line, 2=2xline, 3=both
    % recipe.addStatement("SR830_3", "writeline(h, ""rmod 0"");"); % Reserve mode: 0=high, 1=normal, 2=low
    % recipe.addStatement("SR830_3", "writeline(h, ""slp 0"");"); % Output filter slope: 0=6dB, 1=12dB, 2=18dB, 3=24dB
    % Optional SR830 channels (commented by default):
    % recipe.addChannel("SR830_3", "X", SR830_3_keyword + "_X");
    % recipe.addChannel("SR830_3", "Y", SR830_3_keyword + "_Y");
    % recipe.addChannel("SR830_3", "R", SR830_3_keyword + "_R");
    % recipe.addChannel("SR830_3", "Theta", SR830_3_keyword + "_Theta");
    % recipe.addChannel("SR830_3", "frequency", SR830_3_keyword + "_Freq");
    % recipe.addChannel("SR830_3", "amplitude", SR830_3_keyword + "_V_exc");
    % recipe.addChannel("SR830_3", "aux_in_1", "SR830_3_aux_in_1");
    % recipe.addChannel("SR830_3", "aux_in_2", "SR830_3_aux_in_2");
    % recipe.addChannel("SR830_3", "aux_in_3", "SR830_3_aux_in_3");
    % recipe.addChannel("SR830_3", "aux_in_4", "SR830_3_aux_in_4");
    % recipe.addChannel("SR830_3", "aux_out_1", "SR830_3_aux_out_1");
    % recipe.addChannel("SR830_3", "aux_out_2", "SR830_3_aux_out_2");
    % recipe.addChannel("SR830_3", "aux_out_3", "SR830_3_aux_out_3");
    % recipe.addChannel("SR830_3", "aux_out_4", "SR830_3_aux_out_4");
    recipe.addChannel("SR830_3", "sensitivity", SR830_3_keyword + "_Sens");
    % recipe.addChannel("SR830_3", "time_constant", SR830_3_keyword + "_tau");
    % recipe.addChannel("SR830_3", "sync_filter", SR830_3_keyword + "_sync");
    % recipe.addChannel("SR830_3", "XY", SR830_3_keyword + "_XY");
    recipe.addChannel("SR830_3", "XTheta", SR830_3_keyword + "_XTheta");
    % recipe.addChannel("SR830_3", "YTheta", SR830_3_keyword + "_YTheta");
    % recipe.addChannel("SR830_3", "RTheta", SR830_3_keyword + "_RTheta");
end

if SR860_4_Use
    recipe.addInstrument("handle_SR860_4", "instrument_SR860", "SR860_4", gpibAddress(SR860_4_GPIB, adaptorIndex));
    recipe.addStatement("SR860_4", "handle_SR860_4.requireSetCheck = false;");
    % Optional SR860 frontend settings (commented by default):
    % recipe.addStatement("SR860_4", "h = handle_SR860_4.communicationHandle;");
    % recipe.addStatement("SR860_4", "writeline(h, ""isrc 1"");"); % Input source: 0=A, 1=A-B
    % recipe.addStatement("SR860_4", "writeline(h, ""ivmd 0"");"); % Input source: 0=voltage, 1=current
    % recipe.addStatement("SR860_4", "writeline(h, ""ignd 1"");"); % Input grounding: 0=float, 1=ground
    % recipe.addStatement("SR860_4", "writeline(h, ""icpl 0"");"); % Input coupling: 0=AC, 1=DC
    % Optional SR860 channels (commented by default):
    % recipe.addChannel("SR860_4", "X", SR860_4_keyword + "_X");
    % recipe.addChannel("SR860_4", "Y", SR860_4_keyword + "_Y");
    % recipe.addChannel("SR860_4", "R", SR860_4_keyword + "_R");
    % recipe.addChannel("SR860_4", "Theta", SR860_4_keyword + "_Theta");
    % recipe.addChannel("SR860_4", "frequency", SR860_4_keyword + "_Freq");
    % recipe.addChannel("SR860_4", "amplitude", SR860_4_keyword + "_V_exc");
    % recipe.addChannel("SR860_4", "aux_in_0", "SR860_4_aux_in_0");
    % recipe.addChannel("SR860_4", "aux_in_1", "SR860_4_aux_in_1");
    % recipe.addChannel("SR860_4", "aux_in_2", "SR860_4_aux_in_2");
    % recipe.addChannel("SR860_4", "aux_in_3", "SR860_4_aux_in_3");
    % recipe.addChannel("SR860_4", "aux_out_0", "SR860_4_aux_out_0");
    % recipe.addChannel("SR860_4", "aux_out_1", "SR860_4_aux_out_1");
    % recipe.addChannel("SR860_4", "aux_out_2", "SR860_4_aux_out_2");
    % recipe.addChannel("SR860_4", "aux_out_3", "SR860_4_aux_out_3");
    recipe.addChannel("SR860_4", "sensitivity", SR860_4_keyword + "_Sens");
    % recipe.addChannel("SR860_4", "time_constant", SR860_4_keyword + "_tau");
    % recipe.addChannel("SR860_4", "sync_filter", SR860_4_keyword + "_sync");
    % recipe.addChannel("SR860_4", "XY", SR860_4_keyword + "_XY");
    recipe.addChannel("SR860_4", "XTheta", SR860_4_keyword + "_XTheta");
    % recipe.addChannel("SR860_4", "YTheta", SR860_4_keyword + "_YTheta");
    % recipe.addChannel("SR860_4", "RTheta", SR860_4_keyword + "_RTheta");
    % recipe.addChannel("SR860_4", "dc_offset", SR860_4_keyword + "_dc_offset");
end

if SR830_4_Use
    recipe.addInstrument("handle_SR830_4", "instrument_SR830", "SR830_4", gpibAddress(SR830_4_GPIB, adaptorIndex));
    recipe.addStatement("SR830_4", "handle_SR830_4.requireSetCheck = false;");
    % Optional SR830 frontend settings (commented by default):
    % recipe.addStatement("SR830_4", "h = handle_SR830_4.communicationHandle;");
    % recipe.addStatement("SR830_4", "writeline(h, ""isrc 1"");"); % Input source: 0=A, 1=A-B, 2=I(1MOhm), 3=I(100MOhm)
    % recipe.addStatement("SR830_4", "writeline(h, ""ignd 1"");"); % Input grounding: 0=float, 1=ground
    % recipe.addStatement("SR830_4", "writeline(h, ""icpl 0"");"); % Input coupling: 0=AC, 1=DC
    % recipe.addStatement("SR830_4", "writeline(h, ""ilin 0"");"); % Input line notch filter: 0=none, 1=line, 2=2xline, 3=both
    % recipe.addStatement("SR830_4", "writeline(h, ""rmod 0"");"); % Reserve mode: 0=high, 1=normal, 2=low
    % recipe.addStatement("SR830_4", "writeline(h, ""slp 0"");"); % Output filter slope: 0=6dB, 1=12dB, 2=18dB, 3=24dB
    % Optional SR830 channels (commented by default):
    % recipe.addChannel("SR830_4", "X", SR830_4_keyword + "_X");
    % recipe.addChannel("SR830_4", "Y", SR830_4_keyword + "_Y");
    % recipe.addChannel("SR830_4", "R", SR830_4_keyword + "_R");
    % recipe.addChannel("SR830_4", "Theta", SR830_4_keyword + "_Theta");
    % recipe.addChannel("SR830_4", "frequency", SR830_4_keyword + "_Freq");
    % recipe.addChannel("SR830_4", "amplitude", SR830_4_keyword + "_V_exc");
    % recipe.addChannel("SR830_4", "aux_in_1", "SR830_4_aux_in_1");
    % recipe.addChannel("SR830_4", "aux_in_2", "SR830_4_aux_in_2");
    % recipe.addChannel("SR830_4", "aux_in_3", "SR830_4_aux_in_3");
    % recipe.addChannel("SR830_4", "aux_in_4", "SR830_4_aux_in_4");
    % recipe.addChannel("SR830_4", "aux_out_1", "SR830_4_aux_out_1");
    % recipe.addChannel("SR830_4", "aux_out_2", "SR830_4_aux_out_2");
    % recipe.addChannel("SR830_4", "aux_out_3", "SR830_4_aux_out_3");
    % recipe.addChannel("SR830_4", "aux_out_4", "SR830_4_aux_out_4");
    recipe.addChannel("SR830_4", "sensitivity", SR830_4_keyword + "_Sens");
    % recipe.addChannel("SR830_4", "time_constant", SR830_4_keyword + "_tau");
    % recipe.addChannel("SR830_4", "sync_filter", SR830_4_keyword + "_sync");
    % recipe.addChannel("SR830_4", "XY", SR830_4_keyword + "_XY");
    recipe.addChannel("SR830_4", "XTheta", SR830_4_keyword + "_XTheta");
    % recipe.addChannel("SR830_4", "YTheta", SR830_4_keyword + "_YTheta");
    % recipe.addChannel("SR830_4", "RTheta", SR830_4_keyword + "_RTheta");
end

if SR860_5_Use
    recipe.addInstrument("handle_SR860_5", "instrument_SR860", "SR860_5", gpibAddress(SR860_5_GPIB, adaptorIndex));
    recipe.addStatement("SR860_5", "handle_SR860_5.requireSetCheck = false;");
    % Optional SR860 frontend settings (commented by default):
    % recipe.addStatement("SR860_5", "h = handle_SR860_5.communicationHandle;");
    % recipe.addStatement("SR860_5", "writeline(h, ""isrc 1"");"); % Input source: 0=A, 1=A-B
    % recipe.addStatement("SR860_5", "writeline(h, ""ivmd 0"");"); % Input source: 0=voltage, 1=current
    % recipe.addStatement("SR860_5", "writeline(h, ""ignd 1"");"); % Input grounding: 0=float, 1=ground
    % recipe.addStatement("SR860_5", "writeline(h, ""icpl 0"");"); % Input coupling: 0=AC, 1=DC
    % Optional SR860 channels (commented by default):
    % recipe.addChannel("SR860_5", "X", SR860_5_keyword + "_X");
    % recipe.addChannel("SR860_5", "Y", SR860_5_keyword + "_Y");
    % recipe.addChannel("SR860_5", "R", SR860_5_keyword + "_R");
    % recipe.addChannel("SR860_5", "Theta", SR860_5_keyword + "_Theta");
    % recipe.addChannel("SR860_5", "frequency", SR860_5_keyword + "_Freq");
    % recipe.addChannel("SR860_5", "amplitude", SR860_5_keyword + "_V_exc");
    % recipe.addChannel("SR860_5", "aux_in_0", "SR860_5_aux_in_0");
    % recipe.addChannel("SR860_5", "aux_in_1", "SR860_5_aux_in_1");
    % recipe.addChannel("SR860_5", "aux_in_2", "SR860_5_aux_in_2");
    % recipe.addChannel("SR860_5", "aux_in_3", "SR860_5_aux_in_3");
    % recipe.addChannel("SR860_5", "aux_out_0", "SR860_5_aux_out_0");
    % recipe.addChannel("SR860_5", "aux_out_1", "SR860_5_aux_out_1");
    % recipe.addChannel("SR860_5", "aux_out_2", "SR860_5_aux_out_2");
    % recipe.addChannel("SR860_5", "aux_out_3", "SR860_5_aux_out_3");
    recipe.addChannel("SR860_5", "sensitivity", SR860_5_keyword + "_Sens");
    % recipe.addChannel("SR860_5", "time_constant", SR860_5_keyword + "_tau");
    % recipe.addChannel("SR860_5", "sync_filter", SR860_5_keyword + "_sync");
    % recipe.addChannel("SR860_5", "XY", SR860_5_keyword + "_XY");
    recipe.addChannel("SR860_5", "XTheta", SR860_5_keyword + "_XTheta");
    % recipe.addChannel("SR860_5", "YTheta", SR860_5_keyword + "_YTheta");
    % recipe.addChannel("SR860_5", "RTheta", SR860_5_keyword + "_RTheta");
    % recipe.addChannel("SR860_5", "dc_offset", SR860_5_keyword + "_dc_offset");
end

if SR830_5_Use
    recipe.addInstrument("handle_SR830_5", "instrument_SR830", "SR830_5", gpibAddress(SR830_5_GPIB, adaptorIndex));
    recipe.addStatement("SR830_5", "handle_SR830_5.requireSetCheck = false;");
    % Optional SR830 frontend settings (commented by default):
    % recipe.addStatement("SR830_5", "h = handle_SR830_5.communicationHandle;");
    % recipe.addStatement("SR830_5", "writeline(h, ""isrc 1"");"); % Input source: 0=A, 1=A-B, 2=I(1MOhm), 3=I(100MOhm)
    % recipe.addStatement("SR830_5", "writeline(h, ""ignd 1"");"); % Input grounding: 0=float, 1=ground
    % recipe.addStatement("SR830_5", "writeline(h, ""icpl 0"");"); % Input coupling: 0=AC, 1=DC
    % recipe.addStatement("SR830_5", "writeline(h, ""ilin 0"");"); % Input line notch filter: 0=none, 1=line, 2=2xline, 3=both
    % recipe.addStatement("SR830_5", "writeline(h, ""rmod 0"");"); % Reserve mode: 0=high, 1=normal, 2=low
    % recipe.addStatement("SR830_5", "writeline(h, ""slp 0"");"); % Output filter slope: 0=6dB, 1=12dB, 2=18dB, 3=24dB
    % Optional SR830 channels (commented by default):
    % recipe.addChannel("SR830_5", "X", SR830_5_keyword + "_X");
    % recipe.addChannel("SR830_5", "Y", SR830_5_keyword + "_Y");
    % recipe.addChannel("SR830_5", "R", SR830_5_keyword + "_R");
    % recipe.addChannel("SR830_5", "Theta", SR830_5_keyword + "_Theta");
    % recipe.addChannel("SR830_5", "frequency", SR830_5_keyword + "_Freq");
    % recipe.addChannel("SR830_5", "amplitude", SR830_5_keyword + "_V_exc");
    % recipe.addChannel("SR830_5", "aux_in_1", "SR830_5_aux_in_1");
    % recipe.addChannel("SR830_5", "aux_in_2", "SR830_5_aux_in_2");
    % recipe.addChannel("SR830_5", "aux_in_3", "SR830_5_aux_in_3");
    % recipe.addChannel("SR830_5", "aux_in_4", "SR830_5_aux_in_4");
    % recipe.addChannel("SR830_5", "aux_out_1", "SR830_5_aux_out_1");
    % recipe.addChannel("SR830_5", "aux_out_2", "SR830_5_aux_out_2");
    % recipe.addChannel("SR830_5", "aux_out_3", "SR830_5_aux_out_3");
    % recipe.addChannel("SR830_5", "aux_out_4", "SR830_5_aux_out_4");
    recipe.addChannel("SR830_5", "sensitivity", SR830_5_keyword + "_Sens");
    % recipe.addChannel("SR830_5", "time_constant", SR830_5_keyword + "_tau");
    % recipe.addChannel("SR830_5", "sync_filter", SR830_5_keyword + "_sync");
    % recipe.addChannel("SR830_5", "XY", SR830_5_keyword + "_XY");
    recipe.addChannel("SR830_5", "XTheta", SR830_5_keyword + "_XTheta");
    % recipe.addChannel("SR830_5", "YTheta", SR830_5_keyword + "_YTheta");
    % recipe.addChannel("SR830_5", "RTheta", SR830_5_keyword + "_RTheta");
end

if K2450_A_Use && ~strainController_Use
    recipe.addInstrument("handle_K2450_A", "instrument_K2450", "K2450_A", gpibAddress(K2450_A_GPIB, adaptorIndex));
    recipe.addStatement("K2450_A", "handle_K2450_A.requireSetCheck = false;");
    recipe.addStatement("K2450_A", "h = handle_K2450_A.communicationHandle;");
    recipe.addStatement("K2450_A", "writeline(h, ':SOURce:VOLTage:READ:BACK OFF');");
    recipe.addStatement("K2450_A", "writeline(h, ':SENSe:CURRent:AZERo:STATe OFF');");
    recipe.addStatement("K2450_A", "writeline(h, ':SENSe:CURRent:AVERage:STATe OFF');");
    recipe.addStatement("K2450_A", "writeline(h, ':SOURce:DELay 0');");
    recipe.addStatement("K2450_A", "writeline(h, ':SENSe:CURRent:RANGe 1e-7');");
    recipe.addStatement("K2450_A", "writeline(h, ':SOURce:VOLTage:ILIMit 1e-7');");
    recipe.addStatement("K2450_A", "writeline(h, ':SOURce:VOLTage:RANGe 20');");
    recipe.addStatement("K2450_A", "writeline(h, ':SENSe:CURRent:NPLCycles 0.5');");
    recipe.addStatement("K2450_A", "writeline(h, ':OUTPut ON');");
    recipe.addStatement("K2450_A", "pause(2);");
    recipe.addChannel("K2450_A", "V_source", "V_" + K2450_A_keyword, 1, 0.5, -10, 10); % 1 V/s ramp rate, 0.5 V threshold
    recipe.addChannel("K2450_A", "I_measure", "I_" + K2450_A_keyword);
    recipe.addChannel("K2450_A", "VI", "VI_" + K2450_A_keyword);
end

if K2450_B_Use && ~strainController_Use
    recipe.addInstrument("handle_K2450_B", "instrument_K2450", "K2450_B", gpibAddress(K2450_B_GPIB, adaptorIndex));
    recipe.addStatement("K2450_B", "handle_K2450_B.requireSetCheck = false;");
    recipe.addStatement("K2450_B", "h = handle_K2450_B.communicationHandle;");
    recipe.addStatement("K2450_B", "writeline(h, ':SOURce:VOLTage:READ:BACK OFF');");
    recipe.addStatement("K2450_B", "writeline(h, ':SENSe:CURRent:AZERo:STATe OFF');");
    recipe.addStatement("K2450_B", "writeline(h, ':SENSe:CURRent:AVERage:STATe OFF');");
    recipe.addStatement("K2450_B", "writeline(h, ':SOURce:DELay 0');");
    recipe.addStatement("K2450_B", "writeline(h, ':SENSe:CURRent:RANGe 1e-7');");
    recipe.addStatement("K2450_B", "writeline(h, ':SOURce:VOLTage:ILIMit 1e-7');");
    recipe.addStatement("K2450_B", "writeline(h, ':SOURce:VOLTage:RANGe 20');");
    recipe.addStatement("K2450_B", "writeline(h, ':SENSe:CURRent:NPLCycles 0.5');");
    recipe.addStatement("K2450_B", "writeline(h, ':OUTPut ON');");
    recipe.addStatement("K2450_B", "pause(2);");
    recipe.addChannel("K2450_B", "V_source", "V_" + K2450_B_keyword, 1, 0.5, -10, 10); % 1 V/s ramp rate, 0.5 V threshold
    recipe.addChannel("K2450_B", "I_measure", "I_" + K2450_B_keyword);
    recipe.addChannel("K2450_B", "VI", "VI_" + K2450_B_keyword);
end

if K2450_C_Use
    recipe.addInstrument("handle_K2450_C", "instrument_K2450", "K2450_C", gpibAddress(K2450_C_GPIB, adaptorIndex));
    recipe.addStatement("K2450_C", "handle_K2450_C.requireSetCheck = false;");
    recipe.addStatement("K2450_C", "h = handle_K2450_C.communicationHandle;");
    recipe.addStatement("K2450_C", "writeline(h, ':SOURce:VOLTage:READ:BACK OFF');");
    recipe.addStatement("K2450_C", "writeline(h, ':SENSe:CURRent:AZERo:STATe OFF');");
    recipe.addStatement("K2450_C", "writeline(h, ':SENSe:CURRent:AVERage:STATe OFF');");
    recipe.addStatement("K2450_C", "writeline(h, ':SOURce:DELay 0');");
    recipe.addStatement("K2450_C", "writeline(h, ':SENSe:CURRent:RANGe 1e-7');");
    recipe.addStatement("K2450_C", "writeline(h, ':SOURce:VOLTage:ILIMit 1e-7');");
    recipe.addStatement("K2450_C", "writeline(h, ':SOURce:VOLTage:RANGe 20');");
    recipe.addStatement("K2450_C", "writeline(h, ':SENSe:CURRent:NPLCycles 0.5');");
    recipe.addStatement("K2450_C", "writeline(h, ':OUTPut ON');");
    recipe.addStatement("K2450_C", "pause(2);");
    recipe.addChannel("K2450_C", "V_source", "V_" + K2450_C_keyword, 1, 0.5, -10, 10); % 1 V/s ramp rate, 0.5 V threshold
    recipe.addChannel("K2450_C", "I_measure", "I_" + K2450_C_keyword);
    recipe.addChannel("K2450_C", "VI", "VI_" + K2450_C_keyword);
end

if K2400_A_Use
    recipe.addInstrument("handle_K2400_A", "instrument_K2400", "K2400_A", gpibAddress(K2400_A_GPIB, adaptorIndex));
    recipe.addStatement("K2400_A", "handle_K2400_A.requireSetCheck = false;");
    recipe.addStatement("K2400_A", "h = handle_K2400_A.communicationHandle;");
    recipe.addStatement("K2400_A", "writeline(h, ':SOURce:DELay 0');");
    recipe.addStatement("K2400_A", "writeline(h, ':SYSTem:AZERo:STATe OFF');");
    recipe.addStatement("K2400_A", "writeline(h, ':SENSe:AVERage:STATe OFF');");
    recipe.addStatement("K2400_A", "writeline(h, ':SENSe:CURRent:RANGe 1e-7');");
    recipe.addStatement("K2400_A", "writeline(h, ':SENSe:CURRent:PROTection 1e-7');");
    recipe.addStatement("K2400_A", "writeline(h, ':SOURce:VOLTage:RANGe 20');");
    recipe.addStatement("K2400_A", "writeline(h, ':CURRent:NPLCycles 0.5');");
    recipe.addStatement("K2400_A", "writeline(h, ':OUTPut ON');");
    recipe.addStatement("K2400_A", "pause(2);");
    recipe.addChannel("K2400_A", "V_source", "V_" + K2400_A_keyword, 1, 0.5, -10, 10); % 1 V/s ramp rate, 0.5 V threshold
    recipe.addChannel("K2400_A", "I_measure", "I_" + K2400_A_keyword);
    recipe.addChannel("K2400_A", "VI", "VI_" + K2400_A_keyword);
end

if K2400_B_Use
    recipe.addInstrument("handle_K2400_B", "instrument_K2400", "K2400_B", gpibAddress(K2400_B_GPIB, adaptorIndex));
    recipe.addStatement("K2400_B", "handle_K2400_B.requireSetCheck = false;");
    recipe.addStatement("K2400_B", "h = handle_K2400_B.communicationHandle;");
    recipe.addStatement("K2400_B", "writeline(h, ':SOURce:DELay 0');");
    recipe.addStatement("K2400_B", "writeline(h, ':SYSTem:AZERo:STATe OFF');");
    recipe.addStatement("K2400_B", "writeline(h, ':SENSe:AVERage:STATe OFF');");
    recipe.addStatement("K2400_B", "writeline(h, ':SENSe:CURRent:RANGe 1e-7');");
    recipe.addStatement("K2400_B", "writeline(h, ':SENSe:CURRent:PROTection 1e-7');");
    recipe.addStatement("K2400_B", "writeline(h, ':SOURce:VOLTage:RANGe 20');");
    recipe.addStatement("K2400_B", "writeline(h, ':CURRent:NPLCycles 0.5');");
    recipe.addStatement("K2400_B", "writeline(h, ':OUTPut ON');");
    recipe.addStatement("K2400_B", "pause(2);");
    recipe.addChannel("K2400_B", "V_source", "V_" + K2400_B_keyword, 1, 0.5, -10, 10); % 1 V/s ramp rate, 0.5 V threshold
    recipe.addChannel("K2400_B", "I_measure", "I_" + K2400_B_keyword);
    recipe.addChannel("K2400_B", "VI", "VI_" + K2400_B_keyword);
end

if K2400_C_Use
    recipe.addInstrument("handle_K2400_C", "instrument_K2400", "K2400_C", gpibAddress(K2400_C_GPIB, adaptorIndex));
    recipe.addStatement("K2400_C", "handle_K2400_C.requireSetCheck = false;");
    recipe.addStatement("K2400_C", "h = handle_K2400_C.communicationHandle;");
    recipe.addStatement("K2400_C", "writeline(h, ':SOURce:DELay 0');");
    recipe.addStatement("K2400_C", "writeline(h, ':SYSTem:AZERo:STATe OFF');");
    recipe.addStatement("K2400_C", "writeline(h, ':SENSe:AVERage:STATe OFF');");
    recipe.addStatement("K2400_C", "writeline(h, ':SENSe:CURRent:RANGe 1e-7');");
    recipe.addStatement("K2400_C", "writeline(h, ':SENSe:CURRent:PROTection 1e-7');");
    recipe.addStatement("K2400_C", "writeline(h, ':SOURce:VOLTage:RANGe 20');");
    recipe.addStatement("K2400_C", "writeline(h, ':CURRent:NPLCycles 0.5');");
    recipe.addStatement("K2400_C", "writeline(h, ':OUTPut ON');");
    recipe.addStatement("K2400_C", "pause(2);");
    recipe.addChannel("K2400_C", "V_source", "V_" + K2400_C_keyword, 1, 0.5, -10, 10); % 1 V/s ramp rate, 0.5 V threshold
    recipe.addChannel("K2400_C", "I_measure", "I_" + K2400_C_keyword);
    recipe.addChannel("K2400_C", "VI", "VI_" + K2400_C_keyword);
end

if HP34401A_A_Use
    recipe.addInstrument("handle_HP34401A_A", "instrument_HP34401A", "HP34401A_A", gpibAddress(HP34401A_A_GPIB, adaptorIndex));
    recipe.addStatement("HP34401A_A", "h = handle_HP34401A_A.communicationHandle;");
    recipe.addStatement("HP34401A_A", "writeline(h, ':CONF:VOLT:DC');");
    recipe.addStatement("HP34401A_A", "writeline(h, ':VOLT:DC:NPLC 0.5');");
    % recipe.addStatement("HP34401A_A", "handle_HP34401A_A.reset();");
    recipe.addChannel("HP34401A_A", "value", "HP34401A_A_value");
end

if HP34401A_B_Use
    recipe.addInstrument("handle_HP34401A_B", "instrument_HP34401A", "HP34401A_B", gpibAddress(HP34401A_B_GPIB, adaptorIndex));
    recipe.addStatement("HP34401A_B", "h = handle_HP34401A_B.communicationHandle;");
    recipe.addStatement("HP34401A_B", "writeline(h, ':CONF:VOLT:DC');");
    recipe.addStatement("HP34401A_B", "writeline(h, ':VOLT:DC:NPLC 0.5');");
    % recipe.addStatement("HP34401A_B", "handle_HP34401A_B.reset();");
    recipe.addChannel("HP34401A_B", "value", "HP34401A_B_value");
end

if K10CR1_Use
    recipe.addInstrument("handle_K10CR1", "instrument_K10CR1", "K10CR1", K10CR1_Serial);
    recipe.addChannel("K10CR1", "position_deg", "K10CR1_position_deg");
end

if CS165MU_Use
    recipe.addInstrument("handle_CS165MU", "instrument_CS165MU", "CS165MU", CS165MU_Serial);
    recipe.addStatement("CS165MU", "handle_CS165MU.requireSetCheck = false;");
    recipe.addChannel("CS165MU", "continuous", "CS165MU_continuous");
    recipe.addChannel("CS165MU", "exposure_ms", "CS165MU_exposure_ms");
    recipe.addChannel("CS165MU", "bin", "CS165MU_bin");
    recipe.addChannel("CS165MU", "roi_origin_x_px", "CS165MU_roi_x_px");
    recipe.addChannel("CS165MU", "roi_origin_y_px", "CS165MU_roi_y_px");
    recipe.addChannel("CS165MU", "roi_width_px", "CS165MU_roi_w_px");
    recipe.addChannel("CS165MU", "roi_height_px", "CS165MU_roi_h_px");
    recipe.addChannel("CS165MU", "queued_frames", "CS165MU_queued_frames");
end

if Andor_Use
    recipe.addInstrument("handle_AndorSpectrometer", "instrument_AndorSpectrometer", "AndorSpectrometer", "AndorSpectrometer");
    recipe.addStatement("AndorSpectrometer", "handle_AndorSpectrometer.minTimeBetweenAcquisitions_s = 300;");
    recipe.addStatement("AndorSpectrometer", "rack.batchGetTimeout = minutes(10);");
    recipe.addChannel("AndorSpectrometer", "temperature_C", "CCD_T_C");
    recipe.addChannel("AndorSpectrometer", "exposure_time", "exposure");
    recipe.addChannel("AndorSpectrometer", "center_wavelength_nm", "center_wavelength_nm");
    recipe.addChannel("AndorSpectrometer", "grating", "grating");
    recipe.addChannel("AndorSpectrometer", "pixel_index", "pixel_index");
    recipe.addChannel("AndorSpectrometer", "wavelength_nm", "wavelength_nm");
    recipe.addChannel("AndorSpectrometer", "counts_single", "CCD_counts_1x");
    recipe.addChannel("AndorSpectrometer", "counts_double", "CCD_counts_2x");
    recipe.addChannel("AndorSpectrometer", "counts_triple", "CCD_counts_3x");
    recipe.addStatement("AndorSpectrometer", "handle_AndorSpectrometer.currentGratingInfo();");
end

if attoDRY2100_Use
    recipe.addInstrument("handle_attoDRY2100", "instrument_attoDRY2100", "attoDRY2100", attoDRY2100_Address);
    recipe.addChannel("attoDRY2100", "T", "T");
    recipe.addChannel("attoDRY2100", "B", "B");
    recipe.addChannel("attoDRY2100", "driven", "driven");
end

if ANC300_Use
    recipe.addInstrument("handle_ANC300", "instrument_ANC300", "ANC300", ANC300_Serial);
    recipe.addStatement("ANC300", "handle_ANC300.requireSetCheck = false;");
    recipe.addChannel("ANC300", "voltage_x", "ANC300_Vx", [], [], 0, 60);
    recipe.addChannel("ANC300", "voltage_y", "ANC300_Vy", [], [], 0, 60);
    recipe.addChannel("ANC300", "voltage_z", "ANC300_Vz", [], [], 0, 60);
    recipe.addChannel("ANC300", "frequency_x", "ANC300_fx", [], [], 1, 10000);
    recipe.addChannel("ANC300", "frequency_y", "ANC300_fy", [], [], 1, 10000);
    recipe.addChannel("ANC300", "frequency_z", "ANC300_fz", [], [], 1, 10000);
    % Optional one-shot step command:
    % recipe.addStatement("ANC300", "handle_ANC300.stepAxis(""x"", 100);");
end

if ST3215HS_Use
    recipe.addInstrument("handle_ST3215HS", "instrument_ST3215HS", "ST3215HS", ST3215HS_Serial, servoId_1 = 12, servoId_2 = 13);
    recipe.addChannel("ST3215HS", "position_1_deg", "ST3215HS_pos1_deg");
    recipe.addChannel("ST3215HS", "load_1_percent", "ST3215HS_load1_percent");
    % 0 = direct set, 1 = setPositionConsistent
    recipe.addChannel("ST3215HS", "setConsistently_1", "ST3215HS_setConsistently1", [], [], 0, 1);
    % recipe.addStatement("ST3215HS", "handle_ST3215HS.calibrateSoftLimits(1, loadThreshold_percent = 6);");
    recipe.addChannel("ST3215HS", "position_2_deg", "ST3215HS_pos2_deg");
    recipe.addChannel("ST3215HS", "load_2_percent", "ST3215HS_load2_percent");
    % 0 = direct set, 1 = setPositionConsistent
    recipe.addChannel("ST3215HS", "setConsistently_2", "ST3215HS_setConsistently2", [], [], 0, 1);
    % recipe.addStatement("ST3215HS", "handle_ST3215HS.calibrateSoftLimits(2, loadThreshold_percent = 6);");
end

% Attodry autofocus optics: camera BS + LED BS (beamsplitters)
if ST3215HS_BS_Use
    recipe.addInstrument("handle_ST3215HS_BS", "instrument_ST3215HS", "ST3215HS_BS", ST3215HS_BS_Serial, servoId_1 = 10, servoId_2 = 11);
    recipe.addChannel("ST3215HS_BS", "position_1_deg", "BS_camera_pos_deg");
    recipe.addChannel("ST3215HS_BS", "load_1_percent", "BS_camera_load_percent");
    recipe.addChannel("ST3215HS_BS", "setConsistently_1", "BS_camera_setConsistently", [], [], 0, 1);
    recipe.addChannel("ST3215HS_BS", "position_2_deg", "BS_LED_pos_deg");
    recipe.addChannel("ST3215HS_BS", "load_2_percent", "BS_LED_load_percent");
    recipe.addChannel("ST3215HS_BS", "setConsistently_2", "BS_LED_setConsistently", [], [], 0, 1);
    % recipe.addStatement("ST3215HS_BS", "handle_ST3215HS_BS.calibrateSoftLimits(1, loadThreshold_percent = 6);");
    % recipe.addStatement("ST3215HS_BS", "handle_ST3215HS_BS.calibrateSoftLimits(2, loadThreshold_percent = 6);");
end

% Attodry autofocus optics: red beam block + red ND
if ST3215HS_red_Use
    recipe.addInstrument("handle_ST3215HS_red", "instrument_ST3215HS", "ST3215HS_red", ST3215HS_red_Serial, servoId_1 = 20, servoId_2 = 21);
    recipe.addChannel("ST3215HS_red", "position_1_deg", "block_red_pos_deg");
    recipe.addChannel("ST3215HS_red", "load_1_percent", "block_red_load_percent");
    recipe.addChannel("ST3215HS_red", "setConsistently_1", "block_red_setConsistently", [], [], 0, 1);
    recipe.addChannel("ST3215HS_red", "position_2_deg", "ND_red_pos_deg");
    recipe.addChannel("ST3215HS_red", "load_2_percent", "ND_red_load_percent");
    recipe.addChannel("ST3215HS_red", "setConsistently_2", "ND_red_setConsistently", [], [], 0, 1);
    % recipe.addStatement("ST3215HS_red", "handle_ST3215HS_red.calibrateSoftLimits(1, loadThreshold_percent = 6);");
    % recipe.addStatement("ST3215HS_red", "handle_ST3215HS_red.calibrateSoftLimits(2, loadThreshold_percent = 6);");
end

% Attodry autofocus optics: green beam block + green ND
if ST3215HS_green_Use
    recipe.addInstrument("handle_ST3215HS_green", "instrument_ST3215HS", "ST3215HS_green", ST3215HS_green_Serial, servoId_1 = 22, servoId_2 = 23);
    recipe.addChannel("ST3215HS_green", "position_1_deg", "block_green_pos_deg");
    recipe.addChannel("ST3215HS_green", "load_1_percent", "block_green_load_percent");
    recipe.addChannel("ST3215HS_green", "setConsistently_1", "block_green_setConsistently", [], [], 0, 1);
    recipe.addChannel("ST3215HS_green", "position_2_deg", "ND_green_pos_deg");
    recipe.addChannel("ST3215HS_green", "load_2_percent", "ND_green_load_percent");
    recipe.addChannel("ST3215HS_green", "setConsistently_2", "ND_green_setConsistently", [], [], 0, 1);
    % recipe.addStatement("ST3215HS_green", "handle_ST3215HS_green.calibrateSoftLimits(1, loadThreshold_percent = 6);");
    % recipe.addStatement("ST3215HS_green", "handle_ST3215HS_green.calibrateSoftLimits(2, loadThreshold_percent = 6);");
end

if colorLED_Use
    recipe.addInstrument("handle_colorLED", "instrument_colorLED", "colorLED", colorLED_Serial);
    recipe.addChannel("colorLED", "R", "colorLED_R", [], [], 0, 1);
    recipe.addChannel("colorLED", "G", "colorLED_G", [], [], 0, 1);
    recipe.addChannel("colorLED", "B", "colorLED_B", [], [], 0, 1);
    recipe.addChannel("colorLED", "RGB", "colorLED_RGB", [], [], 0, 1);
end

if USB6001_Use
    recipe.addInstrument("handle_USB6001", "instrument_USB6001", "USB6001", ...
        USB6001_Device, USB6001_numAIChannels, USB6001_accumulations, USB6001_samplingRate_Hz);
    for aiIndex = 0:USB6001_numAIChannels-1
        aiChannelName = "AI" + string(aiIndex);
        recipe.addChannel("USB6001", aiChannelName, "USB6001_" + aiChannelName);
    end
    if USB6001_numAIChannels > 1
        aiVectorChannelName = "AI" + join(string(0:USB6001_numAIChannels-1), "");
        recipe.addChannel("USB6001", aiVectorChannelName, "USB6001_" + aiVectorChannelName);
    end
    recipe.addChannel("USB6001", "AO0", "USB6001_AO0");
    recipe.addChannel("USB6001", "AO1", "USB6001_AO1");
    recipe.addChannel("USB6001", "AO01", "USB6001_AO01");
    recipe.addChannel("USB6001", "accumulations", "USB6001_accumulations");
end

if E4980AL_Use
    recipe.addInstrument("handle_E4980AL", "instrument_E4980AL", "E4980AL", gpibAddress(E4980AL_GPIB, adaptorIndex_strain));
    recipe.addChannel("E4980AL", "Cp", "E4980_Cp");
    recipe.addChannel("E4980AL", "Q", "E4980_Q");
    recipe.addChannel("E4980AL", "CpQ", "E4980_CpQ");
end

if BK889B_Use
    recipe.addInstrument("handle_BK889B", "instrument_BK889B", "BK889B", BK889B_Serial);
    recipe.addChannel("BK889B", "Cp", "BK_Cp");
    recipe.addChannel("BK889B", "Q", "BK_Q");
    recipe.addChannel("BK889B", "CpQ", "BK_CpQ");
end

if MFLI_Use
    recipe.addInstrument("handle_MFLI", "instrument_MFLI", "MFLI", MFLI_Address);
    for i = 1:4
        recipe.addChannel("MFLI", "amplitude_" + string(i), "A" + string(i), [], [], -2, 2);
        recipe.addChannel("MFLI", "phase_" + string(i), "Th" + string(i));
        recipe.addChannel("MFLI", "signed_amplitude_" + string(i), "As" + string(i), [], [], -2, 2);
        recipe.addChannel("MFLI", "frequency_" + string(i), "f" + string(i));
        recipe.addChannel("MFLI", "harmonic_" + string(i), "Harm" + string(i));
        recipe.addChannel("MFLI", "on_" + string(i), "On" + string(i));
    end
end

if SDG2042X_mixed_Use
    recipe.addInstrument("handle_SDG2042X_mixed", "instrument_SDG2042X_mixed", "SDG2042X_mixed", SDG2042X_mixed_Address, ...
        waveformArraySize = 2^15, ...
        uploadFundamentalFrequencyHz = 1, ...
        internalTimebase = true);
    recipe.addStatement("SDG2042X_mixed", "handle_SDG2042X_mixed.requireSetCheck = true;");
    for i = 1:7
        recipe.addChannel("SDG2042X_mixed", "amplitude_" + string(i), "mix_A_" + string(i));
        recipe.addChannel("SDG2042X_mixed", "phase_" + string(i), "mix_Th_" + string(i));
        recipe.addChannel("SDG2042X_mixed", "frequency_" + string(i), "mix_f_" + string(i));
    end
    recipe.addChannel("SDG2042X_mixed", "global_phase_offset", "mix_Th");
end

if SDG2042X_pure_Use
    recipe.addInstrument("handle_SDG2042X_pure", "instrument_SDG2042X_pure", "SDG2042X_pure", SDG2042X_pure_Address, ...
        waveformArraySize = 2^15, ...
        internalTimebase = false);
    recipe.addStatement("SDG2042X_pure", "handle_SDG2042X_pure.requireSetCheck = true;");
    for i = 1:2
        recipe.addChannel("SDG2042X_pure", "amplitude_" + string(i), "pure_A_" + string(i));
        recipe.addChannel("SDG2042X_pure", "phase_" + string(i), "pure_Th_" + string(i));
        recipe.addChannel("SDG2042X_pure", "frequency_" + string(i), "pure_f_" + string(i));
    end
    recipe.addChannel("SDG2042X_pure", "global_phase_offset", "pure_Th");
end

% DDS CASCADE sync: after both DDS instruments are initialized, trigger a
% master-side CASCADE re-handshake to apply any updated CASCADE settings.
if SDG2042X_mixed_Use && SDG2042X_pure_Use
    recipe.addStatement("SDG2042X_pure", "handle_SDG2042X_mixed.cascadeResyncOnMaster();");
    recipe.addStatement("SDG2042X_pure", "handle_SDG2042X_pure.cascadeResyncOnMaster();");
end

if SDG2042X_mixed_TARB_Use
    recipe.addInstrument("handle_SDG2042X_mixed_TARB", "instrument_SDG2042X_mixed_TARB", "SDG2042X_mixed_TARB", SDG2042X_mixed_TARB_Address, ...
        waveformArraySize = 2^20, ...
        uploadFundamentalFrequencyHz = 1, ...
        internalTimebase = true);
    recipe.addStatement("SDG2042X_mixed_TARB", "handle_SDG2042X_mixed_TARB.requireSetCheck = true;");
    for i = 1:7
        recipe.addChannel("SDG2042X_mixed_TARB", "amplitude_" + string(i), "mixTARB_A_" + string(i));
        recipe.addChannel("SDG2042X_mixed_TARB", "phase_" + string(i), "mixTARB_Th_" + string(i));
        recipe.addChannel("SDG2042X_mixed_TARB", "frequency_" + string(i), "mixTARB_f_" + string(i));
    end
    recipe.addChannel("SDG2042X_mixed_TARB", "global_phase_offset", "mixTARB_Th");
end

%% Virtual Instruments

if virtual_del_V_Use
    recipe.addVirtualInstrument("handle_virtual_del_V", "virtualInstrument_del_V", "virtual_delta", "virtual_delta", ...
        vGetChannelName = "V_WSe2", vSetChannelName = "V_tg");
    recipe.addChannel("virtual_delta", "del_V", "del_V", [], [], -10, 10);
end

if virtual_hysteresis_Use
    recipe.addVirtualInstrument("handle_virtual_hysteresis", "virtualInstrument_hysteresis", "virtual_hysteresis1", "virtual_hysteresis1", ...
        setChannelName = "V_tg", min = -5, max = 5);
    recipe.addChannel("virtual_hysteresis1", "hysteresis", "hys_V_tg", [], [], 0, 1);
end

if virtual_nonlinear_T_Use
    recipe.addVirtualInstrument("handle_virtual_nonlinear_T", "virtualInstrument_nonlinear_T", "virtual_nonlinear_T", "virtual_nonlinear_T", ...
        tSetChannelName = "T", tMin = 4, tMax = 200);
    recipe.addChannel("virtual_nonlinear_T", "nonlinear_T", "T_normalized", [], [], 0, 1);
end

if virtual_nE_Use
    recipe.addVirtualInstrument("handle_virtual_nE", "virtualInstrument_nE", "virtual_nE", "virtual_nE", ...
        vBgChannelName = "V_bg", ...
        vTgChannelName = "V_tg", ...
        vBgLimits = [-6, 6], ...
        vTgLimits = [-6, 6], ...
        vBg_n0E0 = 1, ...
        vTg_n0E0 = -1, ...
        vBg_n0ENot0 = 2, ...
        vTg_n0ENot0 = -2);
    recipe.addChannel("virtual_nE", "n", "n_normalized", [], [], 0, 1);
    recipe.addChannel("virtual_nE", "E", "E_normalized", [], [], 0, 1);
    recipe.addChannel("virtual_nE", "nE_within_bounds", "nE_within_bounds");
    recipe.addChannel("virtual_nE", "skipOutOfBounds", "skipOutOfBounds", [], [], 0, 1);
end

if virtual_attodryAutofocus_Use
    recipe.addVirtualInstrument("handle_virtual_attodryAutofocus", "virtualInstrument_attodryAutofocus", "attodryAutofocus", "attodryAutofocus", ...
        T_channelName = "T", ...
        B_channelName = "B", ...
        cameraInstrumentFriendlyName = "CS165MU", ...
        block_red_positionChannelName = "block_red_pos_deg", ...
        block_green_positionChannelName = "block_green_pos_deg", ...
        ND_red_positionChannelName = "ND_red_pos_deg", ...
        ND_green_positionChannelName = "ND_green_pos_deg", ...
        BS_camera_positionChannelName = "BS_camera_pos_deg", ...
        BS_LED_positionChannelName = "BS_LED_pos_deg", ...
        BS_camera_setConsistentlyChannelName = "BS_camera_setConsistently", ...
        BS_LED_setConsistentlyChannelName = "BS_LED_setConsistently", ...
        ledRgbChannelName = "colorLED_RGB", ...
        ANC300InstrumentFriendlyName = "ANC300", ...
        ANC300_voltage_x_ChannelName = "ANC300_Vx", ...
        ANC300_voltage_y_ChannelName = "ANC300_Vy", ...
        ANC300_voltage_z_ChannelName = "ANC300_Vz");
    recipe.addChannel("attodryAutofocus", "T", "attodry_T", [], [], 0, 400);
    recipe.addChannel("attodryAutofocus", "B", "attodry_B", [], [], -1, 1);
    recipe.addChannel("attodryAutofocus", "color", "attodry_color", [], [], 0, 1);
end


%% wrap up setup
%smready(recipe, singleThreaded = true); % Debug: run recipe on client instead of engine worker.
%smready(recipe, verboseClient=true, verboseWorker=true); % Debug: allow logging to files.
smready(recipe);
