function runValue = smrunGetState()
%SMRUNGETSTATE Return the shared run number (NaN means disabled).

    global smrunConfig

    smrunEnsureGlobals();

    runValue = smrunConfig.run;
end


