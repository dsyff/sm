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
Montana1_IP = "136.167.55.127";
Montana2_IP = "136.167.55.165";
Opticool_IP = "127.0.0.1";
Attodry2100_Address = "192.168.1.1";
MFLI_Address = "dev30037";
SDG2042X_mixed_Address = "USB0::0xF4EC::0xEE38::0123456789::0::INSTR";
SDG2042X_pure_Address = "USB0::0xF4EC::0x1102::SDG2XCAD4R3406::0::INSTR";
SDG2042X_mixed_TARB_Address = SDG2042X_mixed_Address;

K10CR1_Serial = ""; % Leave blank to use the first detected device
BK889B_Serial = "COM3";

% ST3215-HS bus servos via Waveshare Bus Servo Adapter (A)
ST3215HS_Serial = "COM4";

% WS2811 color LED controller (Pico 2 USB CDC)
colorLED_Serial = "COM5";

% Thorlabs CS165MU camera (TLCamera SDK)
CS165MU_Serial = ""; % Leave blank to use the first detected camera


%% GPIB Adaptor Indices - change these to match your setup
% use visadevlist() to find out gpib addresses
adaptorIndex = 0;        % Standard instruments
adaptorIndex_strain = 2; % Strain controller instruments


%% instrument usage flags
counter_Use = 0;
clock_Use = 0;
test_Use = 0; %extra counters for testing
virtual_del_V_Use = 0;
virtual_hysteresis_Use = 0;
virtual_nonlinear_T_Use = 0;
virtual_nE_Use = 0;
toyBLG_Use = 0;

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
Montana1_Use = 0;
Opticool_Use = 0;

strainController_Use = 0;
strain_cryostat = "Opticool"; %Opticool, Montana2

K10CR1_Use = 0;
CS165MU_Use = 0;
Andor_Use = 0;
Attodry2100_Use = 0;

BK889B_Use = 0;
ST3215HS_Use = 0;
colorLED_Use = 0;
E4980AL_Use = 0;
MFLI_Use = 0;
SDG2042X_mixed_Use = 0;
SDG2042X_pure_Use = 0;
SDG2042X_mixed_TARB_Use = 0;


%% Create instrumentRackRecipe
recipe = instrumentRackRecipe();


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

    if strain_cryostat == "Opticool"
        strainCellNumber_default = 1;
    elseif strain_cryostat == "Montana2"
        strainCellNumber_default = 2;
    else
        error("demo:InvalidStrainCryostat", "strain_cryostat must be either 'Opticool' or 'Montana2'");
    end

    recipe.addInstrument("handle_strainController", "instrument_strainController", "strain", "strainController_1", ...
        address_E4980AL = gpibAddress(E4980AL_GPIB, adaptorIndex_strain), ...
        address_K2450_A = gpibAddress(K2450_A_GPIB, adaptorIndex_strain), ...
        address_K2450_B = gpibAddress(K2450_B_GPIB, adaptorIndex_strain), ...
        address_Montana2 = Montana2_IP, ...
        address_Opticool = Opticool_IP, ...
        cryostat = strain_cryostat, ...
        strainCellNumber = strainCellNumber_default, ...
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
end


%% Create other instruments using new sm2
if counter_Use
    recipe.addInstrument("handle_counter", "instrument_counter", "counter", "counter");
    recipe.addStatement("handle_counter.requireSetCheck = false;");
    recipe.addChannel("counter", "count", "count");
end

if clock_Use
    recipe.addInstrument("handle_clock", "instrument_clock", "clock", "clock");
    recipe.addChannel("clock", "timeStamp", "time");
end

if toyBLG_Use
    recipe.addInstrument("handle_toyBLG", "instrument_toyBLG", "toyBLG", "toyBLG");
    recipe.addChannel("toyBLG", "h_tg", "toyBLG_h_tg");
    recipe.addChannel("toyBLG", "h_bg", "toyBLG_h_bg");
    recipe.addChannel("toyBLG", "n0", "toyBLG_n0");
    recipe.addChannel("toyBLG", "D0_V_per_nm", "toyBLG_D0_V_per_nm");
    recipe.addChannel("toyBLG", "V_bg", "toyBLG_V_bg", [], [], -10, 10);
    recipe.addChannel("toyBLG", "V_tg", "toyBLG_V_tg", [], [], -10, 10);
    recipe.addChannel("toyBLG", "Rxx", "toyBLG_Rxx");
end

if K2450_A_Use
    recipe.addInstrument("handle_K2450_A", "instrument_K2450", "K2450_A", gpibAddress(K2450_A_GPIB, adaptorIndex));
    recipe.addStatement("handle_K2450_A.requireSetCheck = false;");
    recipe.addStatement("h = handle_K2450_A.communicationHandle;");
    recipe.addStatement("writeline(h, ':SOURce:VOLTage:READ:BACK OFF');");
    recipe.addStatement("writeline(h, ':SENSe:CURRent:AZERo:STATe OFF');");
    recipe.addStatement("writeline(h, ':SENSe:CURRent:AVERage:STATe OFF');");
    recipe.addStatement("writeline(h, ':SOURce:DELay 0');");
    recipe.addStatement("writeline(h, ':SENSe:CURRent:RANGe 1e-7');");
    recipe.addStatement("writeline(h, ':SOURce:VOLTage:ILIMit 1e-7');");
    recipe.addStatement("writeline(h, ':SOURce:VOLTage:RANGe 20');");
    recipe.addStatement("writeline(h, ':SENSe:CURRent:NPLCycles 0.5');");
    recipe.addStatement("writeline(h, ':OUTPut ON');");
    recipe.addStatement("pause(2);");
    recipe.addChannel("K2450_A", "V_source", "V_bg", 1, 0.5, -10, 10);
    recipe.addChannel("K2450_A", "I_measure", "I_bg");
    recipe.addChannel("K2450_A", "VI", "VI_bg");
end

if K2450_B_Use
    recipe.addInstrument("handle_K2450_B", "instrument_K2450", "K2450_B", gpibAddress(K2450_B_GPIB, adaptorIndex));
    recipe.addStatement("handle_K2450_B.requireSetCheck = false;");
    recipe.addStatement("h = handle_K2450_B.communicationHandle;");
    recipe.addStatement("writeline(h, ':SOURce:VOLTage:READ:BACK OFF');");
    recipe.addStatement("writeline(h, ':SENSe:CURRent:AZERo:STATe OFF');");
    recipe.addStatement("writeline(h, ':SENSe:CURRent:AVERage:STATe OFF');");
    recipe.addStatement("writeline(h, ':SOURce:DELay 0');");
    recipe.addStatement("writeline(h, ':SENSe:CURRent:RANGe 1e-7');");
    recipe.addStatement("writeline(h, ':SOURce:VOLTage:ILIMit 1e-7');");
    recipe.addStatement("writeline(h, ':SOURce:VOLTage:RANGe 20');");
    recipe.addStatement("writeline(h, ':SENSe:CURRent:NPLCycles 0.5');");
    recipe.addStatement("writeline(h, ':OUTPut ON');");
    recipe.addStatement("pause(2);");
    recipe.addChannel("K2450_B", "V_source", "V_tg", 1, 0.5, -10, 10);
    recipe.addChannel("K2450_B", "I_measure", "I_tg");
    recipe.addChannel("K2450_B", "VI", "VI_tg");
end

if K2450_C_Use
    recipe.addInstrument("handle_K2450_C", "instrument_K2450", "K2450_C", gpibAddress(K2450_C_GPIB, adaptorIndex));
    recipe.addStatement("handle_K2450_C.requireSetCheck = false;");
    recipe.addStatement("h = handle_K2450_C.communicationHandle;");
    recipe.addStatement("writeline(h, ':SOURce:VOLTage:READ:BACK OFF');");
    recipe.addStatement("writeline(h, ':SENSe:CURRent:AZERo:STATe OFF');");
    recipe.addStatement("writeline(h, ':SENSe:CURRent:AVERage:STATe OFF');");
    recipe.addStatement("writeline(h, ':SOURce:DELay 0');");
    recipe.addStatement("writeline(h, ':SENSe:CURRent:RANGe 1e-7');");
    recipe.addStatement("writeline(h, ':SOURce:VOLTage:ILIMit 1e-7');");
    recipe.addStatement("writeline(h, ':SOURce:VOLTage:RANGe 20');");
    recipe.addStatement("writeline(h, ':SENSe:CURRent:NPLCycles 0.5');");
    recipe.addStatement("writeline(h, ':OUTPut ON');");
    recipe.addStatement("pause(2);");
    recipe.addChannel("K2450_C", "V_source", "V_tg", 1, 0.5, -10, 10);
    recipe.addChannel("K2450_C", "I_measure", "I_tg");
    recipe.addChannel("K2450_C", "VI", "VI_tg");
end

if K2400_A_Use
    recipe.addInstrument("handle_K2400_A", "instrument_K2400", "K2400_A", gpibAddress(K2400_A_GPIB, adaptorIndex));
    recipe.addStatement("handle_K2400_A.requireSetCheck = false;");
    recipe.addStatement("h = handle_K2400_A.communicationHandle;");
    recipe.addStatement("writeline(h, ':SOURce:DELay 0');");
    recipe.addStatement("writeline(h, ':SYSTem:AZERo:STATe OFF');");
    recipe.addStatement("writeline(h, ':SENSe:AVERage:STATe OFF');");
    recipe.addStatement("writeline(h, ':SENSe:CURRent:RANGe 1e-7');");
    recipe.addStatement("writeline(h, ':SENSe:CURRent:PROTection 1e-7');");
    recipe.addStatement("writeline(h, ':SOURce:VOLTage:RANGe 20');");
    recipe.addStatement("writeline(h, ':CURRent:NPLCycles 0.5');");
    recipe.addStatement("writeline(h, ':OUTPut ON');");
    recipe.addStatement("pause(2);");
    recipe.addChannel("K2400_A", "V_source", "V_bg", 1, 0.5, -10, 10);
    recipe.addChannel("K2400_A", "I_measure", "I_bg");
    recipe.addChannel("K2400_A", "VI", "VI_bg");
end

if K2400_B_Use
    recipe.addInstrument("handle_K2400_B", "instrument_K2400", "K2400_B", gpibAddress(K2400_B_GPIB, adaptorIndex));
    recipe.addStatement("handle_K2400_B.requireSetCheck = false;");
    recipe.addStatement("h = handle_K2400_B.communicationHandle;");
    recipe.addStatement("writeline(h, ':SOURce:DELay 0');");
    recipe.addStatement("writeline(h, ':SYSTem:AZERo:STATe OFF');");
    recipe.addStatement("writeline(h, ':SENSe:AVERage:STATe OFF');");
    recipe.addStatement("writeline(h, ':SENSe:CURRent:RANGe 1e-7');");
    recipe.addStatement("writeline(h, ':SENSe:CURRent:PROTection 1e-7');");
    recipe.addStatement("writeline(h, ':SOURce:VOLTage:RANGe 20');");
    recipe.addStatement("writeline(h, ':CURRent:NPLCycles 0.5');");
    recipe.addStatement("writeline(h, ':OUTPut ON');");
    recipe.addStatement("pause(2);");
    recipe.addChannel("K2400_B", "V_source", "V_tg", 1, 0.5, -10, 10);
    recipe.addChannel("K2400_B", "I_measure", "I_tg");
    recipe.addChannel("K2400_B", "VI", "VI_tg");
end

if K2400_C_Use
    recipe.addInstrument("handle_K2400_C", "instrument_K2400", "K2400_C", gpibAddress(K2400_C_GPIB, adaptorIndex));
    recipe.addStatement("handle_K2400_C.requireSetCheck = false;");
    recipe.addStatement("h = handle_K2400_C.communicationHandle;");
    recipe.addStatement("writeline(h, ':SOURce:DELay 0');");
    recipe.addStatement("writeline(h, ':SYSTem:AZERo:STATe OFF');");
    recipe.addStatement("writeline(h, ':SENSe:AVERage:STATe OFF');");
    recipe.addStatement("writeline(h, ':SENSe:CURRent:RANGe 1e-7');");
    recipe.addStatement("writeline(h, ':SENSe:CURRent:PROTection 1e-7');");
    recipe.addStatement("writeline(h, ':SOURce:VOLTage:RANGe 20');");
    recipe.addStatement("writeline(h, ':CURRent:NPLCycles 0.5');");
    recipe.addStatement("writeline(h, ':OUTPut ON');");
    recipe.addStatement("pause(2);");
    recipe.addChannel("K2400_C", "V_source", "V_tg", 1, 0.5, -10, 10);
    recipe.addChannel("K2400_C", "I_measure", "I_tg");
    recipe.addChannel("K2400_C", "VI", "VI_tg");
end

if K10CR1_Use
    recipe.addInstrument("handle_K10CR1", "instrument_K10CR1", "K10CR1", K10CR1_Serial);
    recipe.addChannel("K10CR1", "position_deg", "K10CR1_position_deg");
end

if CS165MU_Use
    recipe.addInstrument("handle_CS165MU", "instrument_CS165MU", "CS165MU", CS165MU_Serial);
    recipe.addStatement("handle_CS165MU.requireSetCheck = false;");
    recipe.addChannel("CS165MU", "continuous", "CS165MU_continuous");
    recipe.addChannel("CS165MU", "exposure_ms", "CS165MU_exposure_ms");
    recipe.addChannel("CS165MU", "bin", "CS165MU_bin");
    recipe.addChannel("CS165MU", "roi_origin_x_px", "CS165MU_roi_x_px");
    recipe.addChannel("CS165MU", "roi_origin_y_px", "CS165MU_roi_y_px");
    recipe.addChannel("CS165MU", "roi_width_px", "CS165MU_roi_w_px");
    recipe.addChannel("CS165MU", "roi_height_px", "CS165MU_roi_h_px");
    recipe.addChannel("CS165MU", "queued_frames", "CS165MU_queued_frames");
end

if ST3215HS_Use
    recipe.addInstrument("handle_ST3215HS", "instrument_ST3215HS", "ST3215HS", ST3215HS_Serial, servoId_1 = 12, servoId_2 = 13);
    recipe.addChannel("ST3215HS", "position_1_deg", "ST3215HS_pos1_deg");
    recipe.addChannel("ST3215HS", "load_1_percent", "ST3215HS_load1_percent");
    recipe.addStatement("handle_ST3215HS.calibrateSoftLimits(1);");
    recipe.addStatement("if handle_ST3215HS.hasServo2");
    recipe.addStatement("  handle_ST3215HS.calibrateSoftLimits(2);");
    recipe.addStatement("end");
    recipe.addChannel("ST3215HS", "position_2_deg", "ST3215HS_pos2_deg");
    recipe.addChannel("ST3215HS", "load_2_percent", "ST3215HS_load2_percent");
end

if colorLED_Use
    recipe.addInstrument("handle_colorLED", "instrument_colorLED", "colorLED", colorLED_Serial);
    recipe.addChannel("colorLED", "R", "colorLED_R", [], [], 0, 1);
    recipe.addChannel("colorLED", "G", "colorLED_G", [], [], 0, 1);
    recipe.addChannel("colorLED", "B", "colorLED_B", [], [], 0, 1);
    recipe.addChannel("colorLED", "RGB", "colorLED_RGB", [], [], 0, 1);
end

if Andor_Use
    recipe.addInstrument("handle_AndorSpectrometer", "instrument_AndorSpectrometer", "AndorSpectrometer", "AndorSpectrometer");
    recipe.addStatement("handle_AndorSpectrometer.minTimeBetweenAcquisitions_s = 300;");
    recipe.addStatement("rack.batchGetTimeout = minutes(10);");
    recipe.addChannel("AndorSpectrometer", "temperature_C", "CCD_T_C");
    recipe.addChannel("AndorSpectrometer", "exposure_time", "exposure");
    recipe.addChannel("AndorSpectrometer", "center_wavelength_nm", "center_wavelength_nm");
    recipe.addChannel("AndorSpectrometer", "grating", "grating");
    recipe.addChannel("AndorSpectrometer", "pixel_index", "pixel_index");
    recipe.addChannel("AndorSpectrometer", "wavelength_nm", "wavelength_nm");
    recipe.addChannel("AndorSpectrometer", "counts_single", "CCD_counts_1x");
    recipe.addChannel("AndorSpectrometer", "counts_double", "CCD_counts_2x");
    recipe.addChannel("AndorSpectrometer", "counts_triple", "CCD_counts_3x");
    recipe.addStatement("handle_AndorSpectrometer.currentGratingInfo();");
end

if SR860_1_Use
    recipe.addInstrument("handle_SR860_1", "instrument_SR860", "SR860_1", gpibAddress(SR860_1_GPIB, adaptorIndex));
    recipe.addStatement("handle_SR860_1.requireSetCheck = false;");
    recipe.addChannel("SR860_1", "frequency", "Freq");
    recipe.addChannel("SR860_1", "amplitude", "V_exc");
    recipe.addChannel("SR860_1", "sensitivity", "Ixx_Sens");
    recipe.addChannel("SR860_1", "XTheta", "Ixx_XTheta");
end

if SR830_1_Use
    recipe.addInstrument("handle_SR830_1", "instrument_SR830", "SR830_1", gpibAddress(SR830_1_GPIB, adaptorIndex));
    recipe.addStatement("handle_SR830_1.requireSetCheck = false;");
    recipe.addChannel("SR830_1", "frequency", "Freq");
    recipe.addChannel("SR830_1", "amplitude", "V_exc");
    recipe.addChannel("SR830_1", "sensitivity", "Ixx_Sens");
    recipe.addChannel("SR830_1", "XTheta", "Ixx_XTheta");
end

if SR830_2_Use
    recipe.addInstrument("handle_SR830_2", "instrument_SR830", "SR830_2", gpibAddress(SR830_2_GPIB, adaptorIndex));
    recipe.addStatement("handle_SR830_2.requireSetCheck = false;");
    recipe.addChannel("SR830_2", "sensitivity", "Vxx1_Sens");
    recipe.addChannel("SR830_2", "XTheta", "Vxx1_XTheta");
end

if SR830_3_Use
    recipe.addInstrument("handle_SR830_3", "instrument_SR830", "SR830_3", gpibAddress(SR830_3_GPIB, adaptorIndex));
    recipe.addStatement("handle_SR830_3.requireSetCheck = false;");
    recipe.addChannel("SR830_3", "sensitivity", "Vxx2_Sens");
    recipe.addChannel("SR830_3", "XTheta", "Vxx2_XTheta");
end

if SR830_4_Use
    recipe.addInstrument("handle_SR830_4", "instrument_SR830", "SR830_4", gpibAddress(SR830_4_GPIB, adaptorIndex));
    recipe.addStatement("handle_SR830_4.requireSetCheck = false;");
    recipe.addChannel("SR830_4", "sensitivity", "Vxx3_Sens");
    recipe.addChannel("SR830_4", "XTheta", "Vxx3_XTheta");
end

if MFLI_Use
    recipe.addInstrument("handle_MFLI", "instrument_MFLI", "MFLI", MFLI_Address);
    for i = 1:4
        recipe.addChannel("MFLI", "amplitude_" + string(i), "A" + string(i), [], [], -2, 2);
        recipe.addChannel("MFLI", "phase_" + string(i), "Th" + string(i));
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
    recipe.addStatement("handle_SDG2042X_mixed.requireSetCheck = true;");
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
    recipe.addStatement("handle_SDG2042X_pure.requireSetCheck = true;");
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
    recipe.addStatement("handle_SDG2042X_mixed.cascadeResyncOnMaster();");
    recipe.addStatement("handle_SDG2042X_pure.cascadeResyncOnMaster();");
end

if SDG2042X_mixed_TARB_Use
    recipe.addInstrument("handle_SDG2042X_mixed_TARB", "instrument_SDG2042X_mixed_TARB", "SDG2042X_mixed_TARB", SDG2042X_mixed_TARB_Address, ...
        waveformArraySize = 2^20, ...
        uploadFundamentalFrequencyHz = 1, ...
        internalTimebase = true);
    recipe.addStatement("handle_SDG2042X_mixed_TARB.requireSetCheck = true;");
    for i = 1:7
        recipe.addChannel("SDG2042X_mixed_TARB", "amplitude_" + string(i), "mixTARB_A_" + string(i));
        recipe.addChannel("SDG2042X_mixed_TARB", "phase_" + string(i), "mixTARB_Th_" + string(i));
        recipe.addChannel("SDG2042X_mixed_TARB", "frequency_" + string(i), "mixTARB_f_" + string(i));
    end
    recipe.addChannel("SDG2042X_mixed_TARB", "global_phase_offset", "mixTARB_Th");
end

if Montana2_Use
    recipe.addInstrument("handle_Montana2", "instrument_Montana2", "Montana2", Montana2_IP);
    recipe.addChannel("Montana2", "T", "T");
end

if Montana1_Use
    recipe.addInstrument("handle_Montana1", "instrument_Montana1", "Montana1", Montana1_IP);
    recipe.addChannel("Montana1", "T", "T");
end

if Opticool_Use
    recipe.addInstrument("handle_Opticool", "instrument_Opticool", "Opticool", Opticool_IP);
    if ~strainController_Use
        recipe.addChannel("Opticool", "T", "T");
    end
    recipe.addChannel("Opticool", "B", "B");
end

if Attodry2100_Use
    recipe.addInstrument("handle_attodry2100", "instrument_attodry2100", "Attodry2100", Attodry2100_Address);
    recipe.addChannel("Attodry2100", "T", "T");
    recipe.addChannel("Attodry2100", "B", "B");
    recipe.addChannel("Attodry2100", "driven", "driven");
end

if BK889B_Use
    recipe.addInstrument("handle_BK889B", "instrument_BK889B", "BK889B", BK889B_Serial);
    recipe.addChannel("BK889B", "Cp", "BK_Cp");
    recipe.addChannel("BK889B", "Q", "BK_Q");
    recipe.addChannel("BK889B", "CpQ", "BK_CpQ");
end

if E4980AL_Use
    recipe.addInstrument("handle_E4980AL", "instrument_E4980AL", "E4980AL", gpibAddress(E4980AL_GPIB, adaptorIndex_strain));
    recipe.addChannel("E4980AL", "Cp", "E4980_Cp");
    recipe.addChannel("E4980AL", "Q", "E4980_Q");
    recipe.addChannel("E4980AL", "CpQ", "E4980_CpQ");
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
        tSetChannelName = virtual_nonlinear_T_TargetChannel, tMin = 4, tMax = 200);
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


%% wrap up setup
%smready(recipe, singleThreaded = true); % Debug: run recipe on client instead of engine worker.
%smready(recipe, verboseClient=true, verboseWorker=true); % Debug: allow logging to files.
smready(recipe);
