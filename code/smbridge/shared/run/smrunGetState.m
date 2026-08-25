function [runValue, revision] = smrunGetState()
%SMRUNGETSTATE Return the shared run number and state revision.

    global smrunConfig

    smrunEnsureGlobals();

    runValue = smrunConfig.run;
    revision = smrunConfig.revision;
end

