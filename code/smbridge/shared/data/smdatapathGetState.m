function pathStr = smdatapathGetState()
%SMDATAPATHGETSTATE Return the shared data-save directory.

    global smdatapathConfig

    smdatapathEnsureGlobals();

    pathStr = smdatapathConfig.path;
end


