function tf = smrunHasCollision(dataDir, runValue)
%SMRUNHASCOLLISION True when any file uses the specified run prefix.

    tf = false;

    if nargin < 2 || isempty(dataDir) || isnan(runValue)
        return;
    end

    if ~isfolder(dataDir)
        return;
    end

    runValue = mod(round(double(runValue)), 1000);
    runStr = sprintf('%03u', runValue);

    patternWithName = fullfile(dataDir, sprintf('%s_*.mat', runStr));
    if ~isempty(dir(patternWithName))
        tf = true;
        return;
    end

    exactFile = fullfile(dataDir, sprintf('%s.mat', runStr));
    if exist(exactFile, 'file')
        tf = true;
    end
end


