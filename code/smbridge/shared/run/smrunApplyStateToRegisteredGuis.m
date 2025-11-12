function smrunApplyStateToRegisteredGuis(excludeSource)
%SMRUNAPPLYSTATETOREGISTEREDGUIS Broadcast run state to GUIs.

    if nargin < 1
        excludeSource = '';
    end

    if ~strcmp(excludeSource, 'small')
        smrunApplyStateToGui('small');
    end

    if ~strcmp(excludeSource, 'main')
        smrunApplyStateToGui('main');
    end
end


