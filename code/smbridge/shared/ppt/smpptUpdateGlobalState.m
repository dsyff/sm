function smpptUpdateGlobalState(source, enabled, file)
%SMPPTUPDATEGLOBALSTATE Persist PPT settings and notify registered GUIs.

    global smpptConfig

    if nargin < 1 || isempty(source)
        source = '';
    end

    smpptEnsureGlobals();

    if nargin >= 2 && ~isempty(enabled)
        smpptConfig.enabled = logical(enabled);
    end

    if nargin >= 3
        if isempty(file)
            smpptConfig.file = '';
        else
            smpptConfig.file = char(file);
        end
    end

    smpptConfig.lastUpdatedBy = source;

    smpptSyncSmauxFromGlobal();
    smpptApplyStateToRegisteredGuis(source);
end


