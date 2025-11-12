function smrunSyncSmauxFromGlobal()
%SMRUNSYNCSMAUXFROMGLOBAL Mirror run state into smaux for legacy users.

    global smrunConfig smaux

    if isempty(smrunConfig) || ~isstruct(smrunConfig)
        return;
    end

    if ~isstruct(smaux)
        smaux = struct();
    end

    if isnan(smrunConfig.run)
        smaux.run = [];
    else
        smaux.run = uint16(smrunConfig.run);
    end
end


