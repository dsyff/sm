function smdatapathApplyStateToRegisteredGuis(excludeSource)
%SMDATAPATHAPPLYSTATETOREGISTEREDGUIS Broadcast data path to GUIs.

    if nargin < 1
        excludeSource = '';
    end

    if ~strcmp(excludeSource, 'small')
        smdatapathApplyStateToGui('small');
    end

    if ~strcmp(excludeSource, 'main')
        smdatapathApplyStateToGui('main');
    end
end


