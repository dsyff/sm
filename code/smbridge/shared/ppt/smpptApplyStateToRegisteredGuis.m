function smpptApplyStateToRegisteredGuis(excludeSource)
%SMPPTAPPLYSTATETOREGISTEREDGUIS Push PPT settings to known GUIs.

    if nargin < 1
        excludeSource = '';
    end

    if ~strcmp(excludeSource, 'small')
        smpptApplyStateToGui('small');
    end

    if ~strcmp(excludeSource, 'main')
        smpptApplyStateToGui('main');
    end
end


