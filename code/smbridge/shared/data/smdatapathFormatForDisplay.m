function [displayString, tooltipString] = smdatapathFormatForDisplay(pathStr, maxLen)
%SMDATAPATHFORMATFORDISPLAY Generate display and tooltip strings.

    if nargin < 2 || isempty(maxLen)
        maxLen = 40;
    end

    tooltipString = char(pathStr);

    if isempty(pathStr)
        displayString = '';
        return;
    end

    pathStr = char(pathStr);
    seps = strfind(pathStr, filesep);

    if numel(seps) > 1
        displayString = pathStr(seps(end-1)+1:end);
    else
        displayString = pathStr;
    end

    if length(displayString) > maxLen
        displayString = displayString(end-maxLen+1:end);
    end
end


