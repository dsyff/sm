function stopped = waitWithStop_(waitDuration, figHandle, isScanInProgressFcn)
    % Interruptible wait using figure ESC and scan-progress callback.
    stopped = false;
    if isempty(waitDuration)
        return;
    end
    if nargin < 3
        isScanInProgressFcn = [];
    end
    if ~isduration(waitDuration)
        waitDuration = seconds(double(waitDuration));
    end
    waitSeconds = seconds(waitDuration);
    if ~(isfinite(waitSeconds) && waitSeconds > 0)
        return;
    end

    maxStep_s = 0.05;
    remaining = waitSeconds;
    while remaining > 0
        try
            if isequal(get(figHandle, "CurrentCharacter"), char(27))
                set(figHandle, "CurrentCharacter", char(0));
                stopped = true;
                return;
            end
        catch
        end
        if ~isempty(isScanInProgressFcn)
            try
                if ~logical(isScanInProgressFcn())
                    stopped = true;
                    return;
                end
            catch
            end
        end
        step = min(maxStep_s, remaining);
        pause(step);
        remaining = remaining - step;
    end
end

