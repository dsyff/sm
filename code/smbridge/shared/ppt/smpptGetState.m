function [enabled, file] = smpptGetState()
%SMPPTGETSTATE Return the shared PowerPoint configuration.

    global smpptConfig

    smpptEnsureGlobals();

    enabled = logical(smpptConfig.enabled);
    file = smpptConfig.file;
end


