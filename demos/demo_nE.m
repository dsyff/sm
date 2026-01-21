global instrumentRackGlobal smscan smaux smdata bridge tareData; %#ok<NUSED>
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

%% instrument rack
rack = instrumentRack(true);
handle_blg = instrument_toyBLG("blg_test", ...
    h_bg = 30e-9, ...
    h_tg = 20e-9, ...
    n0 = 1E16, ...
    D0_V_per_nm = 0.1);
rack.addInstrument(handle_blg, "blg_test");
rack.addChannel("blg_test", "h_bg", "h_bg");
rack.addChannel("blg_test", "h_tg", "h_tg");
rack.addChannel("blg_test", "n0", "n0");
rack.addChannel("blg_test", "D0_V_per_nm", "D0_V_per_nm");
rack.addChannel("blg_test", "V_bg", "V_bg", [], [], -20, 20);
rack.addChannel("blg_test", "V_tg", "V_tg", [], [], -20, 20);
rack.addChannel("blg_test", "Rxx", "Rxx");

handle_virtual_nE = virtualInstrument_nE("virtual_nE", rack, ...
    vBgChannelName = "V_bg", ...
    vTgChannelName = "V_tg", ...
    vBgLimits = [-13, 14], ...
    vTgLimits = [-11, 10], ...
    vBg_n0E0 = 0.0840, ...
    vTg_n0E0 = -1.1204, ...
    vBg_n0ENot0 = -1.6807, ...
    vTg_n0ENot0 = 0.0560);
rack.addInstrument(handle_virtual_nE, "virtual_nE");
rack.addChannel("virtual_nE", "n", "n", [], [], 0, 1);
rack.addChannel("virtual_nE", "E", "E", [], [], 0, 1);
rack.addChannel("virtual_nE", "nE_within_bounds", "nE_within_bounds");

%% wrap up setup
smready(rack);
