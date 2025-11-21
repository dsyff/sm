function smdatapathUpdateGlobalState(source, pathStr)
%SMDATAPATHUPDATEGLOBALSTATE Persist data-save path and notify GUIs.

    global smdatapathConfig

    if nargin < 1 || isempty(source)
        source = '';
    end

    smdatapathEnsureGlobals();

    if nargin >= 2
        if isempty(pathStr)
            pathStr = smdatapathDefaultPath();
        end
        smdatapathConfig.path = char(pathStr);
    end

    smdatapathConfig.lastUpdatedBy = source;

    smdatapathSyncSmauxFromGlobal();
    smdatapathApplyStateToRegisteredGuis(source);
end


