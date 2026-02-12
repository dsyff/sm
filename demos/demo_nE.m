global smscan smaux smdata bridge; %#ok<NUSED>
%#ok<*GVMIS,*UNRCH>
% NOTE: This demo uses toy/virtual instruments only; no hardware is required.

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

%% instrument rack (recipe, built on worker engine)
recipe = instrumentRackRecipe();

recipe.addInstrument("handle_blg", "instrument_toyBLG", "blg_test", "blg_test", ...
    h_bg = 30e-9, ...
    h_tg = 20e-9, ...
    n0 = 1E16, ...
    D0_V_per_nm = 0.1);

recipe.addChannel("blg_test", "h_bg", "h_bg");
recipe.addChannel("blg_test", "h_tg", "h_tg");
recipe.addChannel("blg_test", "n0", "n0");
recipe.addChannel("blg_test", "D0_V_per_nm", "D0_V_per_nm");
recipe.addChannel("blg_test", "V_bg", "V_bg", [], [], -20, 20);
recipe.addChannel("blg_test", "V_tg", "V_tg", [], [], -20, 20);
recipe.addChannel("blg_test", "Rxx", "Rxx");

recipe.addInstrument("handle_toyA", "instrument_toyA", "instrument_toyA", "instrument_toyA");
recipe.addInstrument("handle_toyB", "instrument_toyB", "instrument_toyB", "instrument_toyB");
recipe.addChannel("instrument_toyA", "A", "toyA_A_size1");
recipe.addChannel("instrument_toyA", "B", "toyA_B_size3");
recipe.addChannel("instrument_toyB", "X", "toyB_X_size2");
recipe.addChannel("instrument_toyB", "Y", "toyB_Y_size4");

recipe.addVirtualInstrument("handle_virtual_nE", "virtualInstrument_nE", "virtual_nE", "virtual_nE", ...
    vBgChannelName = "V_bg", ...
    vTgChannelName = "V_tg", ...
    vBgLimits = [-13, 14], ...
    vTgLimits = [-11, 10], ...
    vBg_n0E0 = 0.0840, ...
    vTg_n0E0 = -1.1204, ...
    vBg_n0ENot0 = -1.6807, ...
    vTg_n0ENot0 = 0.0560);

recipe.addChannel("virtual_nE", "n", "n", [], [], 0, 1);
recipe.addChannel("virtual_nE", "E", "E", [], [], 0, 1);
recipe.addChannel("virtual_nE", "nE_within_bounds", "nE_within_bounds");
recipe.addChannel("virtual_nE", "skipOutOfBounds", "skipOutOfBounds", [], [], 0, 1);

%% wrap up setup
% smready(recipe, singleThreaded = true); % Debug: run recipe on client instead of engine worker.
% In the Queue GUI, Run executes turbo mode (engine worker measurement loop).
smready(recipe, verboseClient=false, verboseWorker=false);
