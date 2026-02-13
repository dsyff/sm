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
K2450_CT_GPIB = 17;
adaptorIndex = 0;

%% instrument rack recipe
recipe = instrumentRackRecipe();

recipe.addInstrument("handle_K2450_CT", "instrument_K2450_CT", "K2450_CT", gpibAddress(K2450_CT_GPIB, adaptorIndex));
recipe.addStatement("handle_K2450_CT.requireSetCheck = false;");
recipe.addStatement("h = handle_K2450_CT.communicationHandle;");
recipe.addStatement("writeline(h, ':SOURce:VOLTage:READ:BACK OFF');");
recipe.addStatement("writeline(h, ':SENSe:CURRent:AZERo:STATe OFF');");
recipe.addStatement("writeline(h, ':SENSe:CURRent:AVERage:STATe OFF');");
recipe.addStatement("writeline(h, ':SOURce:DELay 0');");
recipe.addStatement("writeline(h, ':SOURce:VOLTage:ILIMit 1e-7');");
recipe.addStatement("writeline(h, ':SOURce:VOLTage:RANGe 20');");
recipe.addStatement("writeline(h, ':SENSe:CURRent:NPLCycles 0.5');");
recipe.addStatement("writeline(h, ':OUTPut ON');");
recipe.addStatement("pause(2);");

recipe.addChannel("K2450_CT", "V_source", "V_source", 1, 0.5, -10, 10);
recipe.addChannel("K2450_CT", "I_measure", "I_measure");
recipe.addChannel("K2450_CT", "VI", "VI");

%% wrap up setup
%smready(recipe, singleThreaded = true); % Debug: run recipe on client instead of engine worker.
%smready(recipe, verboseClient=true, verboseWorker=true); % Debug: allow logging to files.
smready(recipe);
