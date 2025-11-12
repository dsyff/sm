function nextValue = smrunIncrement(runValue)
%SMRUNINCREMENT Increment run number with wrap-around at 1000.

    if nargin < 1 || isempty(runValue) || isnan(runValue)
        nextValue = NaN;
        return;
    end

    runValue = mod(round(double(runValue)), 1000);
    nextValue = mod(runValue + 1, 1000);
end


