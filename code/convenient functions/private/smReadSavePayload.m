function [saved, label] = smReadSavePayload(source, fileNum, nThMatch, includeRaw)
% Shared raw MAT loading and numbered-file lookup for smload and smplot.
if nargin < 2, fileNum = []; end
if nargin < 3, nThMatch = []; end
if nargin < 4, includeRaw = false; end

if ~isempty(fileNum) || ~isempty(nThMatch)
    if isempty(fileNum)
        error("smload:MissingFileNumber", "A file number is required when specifying a folder.");
    end
    if isempty(nThMatch), nThMatch = 1; end
    validateattributes(fileNum, "numeric", ["scalar", "integer", "real", "finite", "nonnegative"], mfilename, "fileNum");
    validateattributes(nThMatch, "numeric", ["scalar", "integer", "real", "finite", "positive"], mfilename, "nThMatch");

    folder = string(source);
    listing = dir(fullfile(folder, "*.mat"));
    names = {listing.name};
    prefix = sprintf("%03u", fileNum);
    matches = find(~cellfun("isempty", regexp(names, "^" + prefix + "(?!\d)", "once")) & ~[listing.isdir]);
    isData = false(size(matches));
    for idx = 1:numel(matches)
        variables = whos("-file", fullfile(folder, listing(matches(idx)).name));
        isData(idx) = all(ismember(["scan", "data"], string({variables.name})));
    end
    matches = matches(isData);
    if numel(matches) < nThMatch
        error("smload:NoMatchingFile", "Requested match %d for %s in '%s' exceeds available data files (%d).", ...
            nThMatch, prefix, folder, numel(matches));
    end
    source = fullfile(folder, listing(matches(nThMatch)).name);
    disp("loading " + source);
end

if isstruct(source)
    saved = source;
    label = 'struct input';
else
    if ~((ischar(source) && isrow(source)) || (isstring(source) && isscalar(source)))
        error("smload:InvalidSource", "Filename must be a character vector or string scalar.");
    end
    if ~isfile(source)
        error("smload:MissingFile", "File %s does not exist.", source);
    end
    if includeRaw
        saved = load(source);
    else
        saved = load(source, "scan", "data");
    end
    label = char(source);
end
if ~isscalar(saved) || ~isfield(saved, "scan") || ~isfield(saved, "data")
    error("smload:InvalidPayload", "Save data must contain scan and data fields.");
end
end
