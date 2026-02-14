global engine smscan smaux smdata bridge; %#ok<GVMIS,NUSED>

% Close existing figures from previous sessions (non-forced).
close all;

% Ensure sm-dev code folders on path (avoid instruments/private)
st = dbstack("-completenames");
if isempty(st) || ~isfield(st, "file") || strlength(string(st(1).file)) == 0
    error("sminit:CannotDetermineLocation", "Unable to determine sminit location (dbstack empty).");
end

codeDir = fileparts(string(st(1).file));
addpath(codeDir);

codeEntries = dir(codeDir);
for i = 1:numel(codeEntries)
    if ~codeEntries(i).isdir
        continue;
    end

    name = string(codeEntries(i).name);
    if name == "." || name == ".."
        continue;
    end

    folderPath = fullfile(codeDir, name);
    if name == "instruments"
        % Only top-level instruments folder to avoid adding private subfolders
        addpath(folderPath);
    else
        addpath(genpath(folderPath));
    end
end

% Check MATLAB version (R2024a or newer required)
if isMATLABReleaseOlderThan("R2024a")
    error("sminit: MATLAB version is too old. SM1.5 requires MATLAB R2024a or newer. Current version: " + version("-release"));
end

% Clean up existing engine to release resources
if exist("engine", "var") && ~isempty(engine) && isa(engine, "measurementEngine")
    try
        delete(engine);
    catch ME
        fprintf("sminit deleteEngineFailed: %s\n", ME.message);
    end
    clear engine;
end

delete(visadevfind);
delete(serialportfind);
clearvars codeDir codeEntries folderPath i name st;
%clear all;

