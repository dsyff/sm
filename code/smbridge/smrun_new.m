function data = smrun_new(scan, filename)
% Modified version of smrun that uses the new sm2 system
% data = smrun_new(scan, filename)
% data = smrun_new(filename) will assume scan = smscan
%
% This is a modified version of the original smrun that uses smget_new and smset_new
% NOTE: Ramping and trafofn functionality removed for performance optimization.
%       Use instrument objects for transformations and direct setting.

% Space bar - pauses operation
% Escape key - exits operation gracefully

global smdata;
global smscan;
global smaux;
global instrumentRackGlobal

if ~isstruct(scan) 
    filename=scan;
    scan=smscan;
end

% Set global constants for the scan
if isfield(scan,'consts') && ~isempty(scan.consts)
    if ~isfield(scan.consts,'set')
        [scan.consts.set] = deal(1);  % Vectorized assignment
    end
    % Vectorized extraction of set constants
    set_mask = [scan.consts.set] == 1;
    if any(set_mask)
        setchans = {scan.consts(set_mask).setchan};
        setvals = [scan.consts(set_mask).val];
        % Direct instrumentRack call for maximum efficiency
        channelNames = string(setchans);
        if isrow(channelNames)
            channelNames = channelNames';  % Ensure column vector
        end
        instrumentRackGlobal.rackSet(channelNames, setvals);
    end
end

scandef = scan.loops;

if ~isfield(scan, 'disp') || isempty(scan.disp)
    disp = struct('loop', {}, 'channel', {}, 'dim', {});
else
    disp = scan.disp;
end

nloops = length(scandef);
nsetchan = zeros(1, nloops);
ngetchan = zeros(1, nloops);
tloop = zeros(1, nloops);

% Initialize storage for original vector channel names
original_getchan = cell(1, nloops);
original_setchan = cell(1, nloops);
getchan_strings = cell(1, nloops);
setchan_strings = cell(1, nloops);

% Vectorized field initialization
if ~isfield(scandef, 'npoints')
    [scandef.npoints] = deal([]);
end

if ~isfield(scan, 'saveloop')
    scan.saveloop = [min(2, max(nloops, 2)) 1];
elseif length(scan.saveloop) == 1
    scan.saveloop(2) = 1;
end

if nargin >= 2 && filename(2)~=':'
    if isempty(filename)
        filename = 'data';
    end
    
    if all(filename ~= '/')
        filename = sprintf('sm_%s.mat', filename);
    end
    
    str = '';
    while (exist(filename, 'file') || exist([filename, '.mat'], 'file')) && ~strcmp(str, 'yes')
        while 1
            str = input('File exists. Overwrite? (yes/no): ', 's');
            if strcmp(str, 'yes') || strcmp(str, 'no')
                break;
            end
        end
        if strcmp(str, 'no')
            filename = sprintf('sm_%s.mat', input('Enter new name:', 's'));
        end
    end
end


for i = 1:nloops
    if isempty(scandef(i).npoints)        
        scandef(i).npoints = length(scandef(i).rng);
    elseif isempty(scandef(i).rng)        
        scandef(i).rng = 1:scandef(i).npoints;
    else
        scandef(i).rng = linspace(scandef(i).rng(1), scandef(i).rng(end), scandef(i).npoints);
    end
    
    % Store original vector channel names for efficient smget_new calls
    original_getchan{i} = scandef(i).getchan;
    original_setchan{i} = scandef(i).setchan;
    
    % Pre-convert channel names to column vectors of strings for performance
    if ~isempty(original_getchan{i})
        getchan_strings{i} = string(original_getchan{i});
        if isrow(getchan_strings{i})
            getchan_strings{i} = getchan_strings{i}';
        end
    else
        getchan_strings{i} = string.empty(0,1);  % Empty column vector
    end
    
    if ~isempty(original_setchan{i})
        setchan_strings{i} = string(original_setchan{i});
        if isrow(setchan_strings{i})
            setchan_strings{i} = setchan_strings{i}';
        end
    else
        setchan_strings{i} = string.empty(0,1);  % Empty column vector
    end
    
    scandef(i).setchan = smchanlookup_new(scandef(i).setchan, true);
    scandef(i).getchan = smchanlookup_new(scandef(i).getchan, true);
    nsetchan(i) = length(scandef(i).setchan);
    ngetchan(i) = length(scandef(i).getchan);
end

% Build getch after channel lookup conversion - fully vectorized
all_getchans = {scandef.getchan};
nonempty_mask = ~cellfun(@isempty, all_getchans);
if any(nonempty_mask)
    getch = vertcat(all_getchans{nonempty_mask});
else
    getch = [];
end

npoints = [scandef.npoints];
totpoints = prod(npoints);

datadim = zeros(sum(ngetchan), 5);
data = cell(1, sum(ngetchan));
ndim = zeros(1, sum(ngetchan));
dataloop = zeros(1, sum(ngetchan));
disph = zeros(1, sum(ngetchan));

% Pre-compute all instchan data for efficiency
instchan_data = cell(1, nloops);
for i = 1:nloops
    if ~isempty(scandef(i).getchan)
        instchan_data{i} = reshape([smdata.channels(scandef(i).getchan).instchan], 2, [])';
    else
        instchan_data{i} = [];
    end
end

for i = 1:nloops
    instchan_i = instchan_data{i};
    for j = 1:ngetchan(i)
        ind = sum(ngetchan(1:i-1))+ j;
        dd = smdata.inst(instchan_i(j, 1)).datadim(instchan_i(j, 2), :);
        
        if all(dd <= 1)
            ndim(ind) = 0;
        else
            ndim(ind) = find(dd > 1, 1, 'last');
        end
        
        datadim(ind, 1:ndim(ind)) = dd(1:ndim(ind));
        dim = [npoints(end:-1:i), datadim(ind, 1:ndim(ind))];
        if length(dim) == 1
            dim(2) = 1;
        end
        data{ind} = nan(dim);
        dataloop(ind) = i;
    end
end
   
% Determine subplot layout based on number of displays
switch length(disp)
    case 1,         sbpl = [1 1];         
    case 2,         sbpl = [1 2];
    case {3, 4},    sbpl = [2 2];
    case {5, 6},    sbpl = [2 3];
    case {7, 8, 9}, sbpl = [3 3];
    case {10, 11, 12}, sbpl = [3 4];
    case {13, 14, 15, 16}, sbpl = [4 4];
    case {17, 18, 19, 20}, sbpl = [4 5];
    case {21, 22, 23, 24, 25}, sbpl = [5 5];
    case {26, 27, 28, 29, 30}, sbpl = [5 6];
    otherwise,      sbpl = [6 6]; disp(36:end) = [];
end

% Determine figure number - always use 1000 and overwrite previous scans
if isfield(scan,'figure')
    figurenumber = scan.figure;
    if isnan(figurenumber)
        figurenumber = 1000;
    end
else
    figurenumber = 1000;
end

if ~ishandle(figurenumber)
    figureHandle = figure(figurenumber);
    figureHandle.WindowState = 'maximized';
    % Ensure figure is fully initialized before proceeding
    drawnow;
else
    figure(figurenumber);
    clf;
end

set(figurenumber, 'CurrentCharacter', char(0));

% Set CloseRequestFcn for graceful exit
set(figurenumber, 'CloseRequestFcn', @(src,evt) gracefulClose());


% Set default display loops
if ~isfield(disp, 'loop')
    for i = 1:length(disp)
        disp(i).loop = dataloop(disp(i).channel)-1;
    end
end

s.type = '()';
s2.type = '()';
for i = 1:length(disp)    
    subplot(sbpl(1), sbpl(2), i);
    dc = disp(i).channel;

    s.subs = num2cell(ones(1, nloops - dataloop(dc) + 1 + ndim(dc)));
    [s.subs{end-disp(i).dim+1:end}] = deal(':');
    
    if dataloop(dc) - ndim(dc) < 1 
        x = 1:datadim(dc, ndim(dc));
        xlab = 'n';
    else
        x = scandef(dataloop(dc) - ndim(dc)).rng;        
        if ~isempty(scandef(dataloop(dc) - ndim(dc)).setchan)
            xlab = smdata.channels(scandef(dataloop(dc) - ndim(dc)).setchan(1)).name;
        else
            xlab = '';
        end
    end

    if disp(i).dim == 2        
        if dataloop(dc) - ndim(dc) < 0
            y = 1:datadim(dc, ndim(dc)-1);
            ylab = 'n';
        else
            y = scandef(dataloop(dc) - ndim(dc) + 1).rng;
            if ~isempty(scandef(dataloop(dc) - ndim(dc) + 1).setchan)
                ylab = smdata.channels(scandef(dataloop(dc) - ndim(dc) + 1).setchan(1)).name;
            else
                ylab = '';
            end
        end
        z = NaN(length(y),length(x));
        z(:, :) = subsref(data{dc}, s);
        disph(i) = imagesc(x, y, z);
        
        set(gca, 'ydir', 'normal');
        colorbar;
        if dc <= length(getch)
            title(smdata.channels(getch(dc)).name);
        end
        xlabel(xlab);
        ylabel(ylab);
    else
        y = zeros(size(x));
        y(:) = subsref(data{dc}, s);
        disph(i) = plot(x, y);
        xlim(sort(x([1, end])));
        xlabel(xlab);
        if dc <= length(getch)
            ylabel(smdata.channels(getch(dc)).name);
        end
    end
end  

x = zeros(1, nloops);

if nargin >= 2
    save(filename, 'scan');
end

tic;

count = ones(size(npoints));

% Cache frequently used values
nloops_cached = nloops;
totpoints_cached = totpoints;

% Pre-compute channel index offsets for faster data storage
channel_offsets = cumsum([0, ngetchan(1:end-1)]);

% Pre-compute display update variables for speed
disp_loops = [disp.loop];
disp_channels = [disp.channel];
disp_dims = [disp.dim];

% Cache figure handle checks
scan_should_exit = false;
temp_file_counter = 0;

save_operations_completed = false;

% Find dummy loops
isdummy = false(1, nloops);
for i = 1:nloops
    isdummy(i) = isfield(scandef(i), 'waittime') && ~isempty(scandef(i).waittime) && scandef(i).waittime < 0 ...
        && isempty(scandef(i).getchan) ...
        && ~any(scan.saveloop(1) == i) && ~any([disp.loop] == i);
end

loops = 1:nloops;

% main loop
for point_idx = 1:totpoints_cached    
    if point_idx > 1
        loops_end_idx = 1;
        for idx = 1:nloops_cached
            if count(idx) > 1
                loops_end_idx = idx;
                break;
            end
        end
        loops = 1:loops_end_idx;
    end       
    
    for j = loops
        x(j) = scandef(j).rng(count(j));
    end
    
    for j = fliplr(loops(~isdummy(loops) | count(loops)==1))
        val = x;

        if count(j) == 1
            if nsetchan(j) && ~isempty(setchan_strings{j})
                % Direct instrumentRack call using pre-computed strings
                instrumentRackGlobal.rackSet(setchan_strings{j}, val(j));
                
                if isfield(scandef(j),'startwait')
                    pause(scandef(j).startwait)
                end
            end
            tloop(j) = now;
        else
            if nsetchan(j) > 0 && ~isempty(setchan_strings{j})
                % Direct instrumentRack call using pre-computed strings
                instrumentRackGlobal.rackSet(setchan_strings{j}, val(j));
            end
        end

        if isfield(scandef(j),'waittime') && ~isempty(scandef(j).waittime)
            pause(scandef(j).waittime)
        end
    end
    loops_end_idx = nloops_cached;
    for idx = 1:nloops_cached
        if count(idx) < npoints(idx)
            loops_end_idx = idx;
            break;
        end
    end
    loops = 1:loops_end_idx;
    if loops_end_idx == nloops_cached && all(count >= npoints)
        loops = 1:nloops_cached;
    end
    
    for j = loops(~isdummy(loops))
        % Direct instrumentRack call using pre-computed strings
        if ~isempty(getchan_strings{j})
            newdata = instrumentRackGlobal.rackGet(getchan_strings{j});
            % Convert to cell array to match expected format
            if ~iscell(newdata)
                newdata = num2cell(newdata);
            end
        else
            newdata = {};
        end

        % OPTIMIZED: Direct data storage with pre-computed offsets
        ind_offset = channel_offsets(j);
        for k = 1:ngetchan(j)
            s.subs = [num2cell(count(end:-1:j)), repmat({':'}, 1, ndim(ind_offset + k))];
            data{ind_offset + k} = subsasgn(data{ind_offset + k}, s, newdata{k});
        end
        
        % Update display every point for immediate responsiveness
        % Update displays with cached values for speed
        for k = 1:length(disp)
            if disp_loops(k) == j
                dc = disp_channels(k);
                nind = ndim(dc)+ nloops+1-dataloop(dc)-disp_dims(k);
                s2.subs = [num2cell([count(end:-1:max(j, end-nind+1)), ones(1, max(0, nind+j-1-nloops))]),...
                    repmat({':'},1, disp_dims(k))];
                    try
                        if disp_dims(k) == 2
                            z_data = subsref(data{dc}, s2);
                            set(disph(k), 'cdata', z_data);
                        else                
                            set(disph(k), 'ydata', subsref(data{dc}, s2));
                        end
                    catch ME
                        saveData(); % Ensure data is saved before exiting
                        rethrow(ME);
                    end
            end
        end
        
        drawnow limitrate;

        % Temporary save with proper path handling
        if j == scan.saveloop(1) && ~mod(count(j), scan.saveloop(2)) && nargin >= 2
            try
                temp_file_counter = temp_file_counter + 1;
                [p,f,e] = fileparts(filename);
                if isempty(p)
                    tempfile = sprintf('%s-temp%d%s~', f, temp_file_counter, e);
                else
                    tempfile = sprintf('%s%s%s-temp%d%s~', p, filesep, f, temp_file_counter, e);
                end
                save(tempfile, 'data', 'scan');
            catch
                % Fallback save
                try
                    [~,f,e] = fileparts(filename);
                    save([f '_fallback' e], 'data', 'scan');
                catch
                    % Silent failure for speed
                end
            end
        end
               
    end
    count(loops(1:end-1)) = 1;
    count(loops(end)) =  count(loops(end)) + 1;
    
    %% Optimized exit/pause checks with reduced figure handle calls
    if ishandle(figurenumber)
        current_char = get(figurenumber, 'CurrentCharacter');
        if current_char == char(27)  % Escape key
            set(figurenumber, 'CurrentCharacter', char(0));
            saveData();
            return;
%        elseif current_char == ' '  % Space bar
%            set(figurenumber, 'CurrentCharacter', char(0));
%            evalin('base', 'keyboard');                
        end
    end
    
    % Check if scan should exit (e.g., figure was closed)
    if scan_should_exit
        return;
    end
  
end

% Scan completed normally
saveData();

    % Nested function for data save operations only
    function saveData()
        % Prevent double saving
        if save_operations_completed
            return;
        end
        
        % Save figure if it still exists
        if ishandle(figurenumber)
            try
                if exist('filename', 'var') && ~isempty(filename)
                    figstring = filename(1:length(filename)-4);
                    % Suppress figure file size warning
                    warning('off', 'MATLAB:Figure:FigureSavedToMATFileFormat');
                    warning('off', 'MATLAB:savefig:LargeFigure');
                    saveas(figurenumber, figstring, 'fig');
                    warning('on', 'MATLAB:Figure:FigureSavedToMATFileFormat');
                    warning('on', 'MATLAB:savefig:LargeFigure');
                    print(figurenumber, '-bestfit', figstring, '-dpdf');
                end
            catch ME
                % Figure save failed - continue silently
            end
        end
        
        % Save PowerPoint if enabled
        if exist('smaux', 'var') && isstruct(smaux) && isfield(smaux, 'smgui') && isfield(smaux.smgui, 'appendppt_cbh') && get(smaux.smgui.appendppt_cbh,'Value')
            try
                % Create text structure for smsaveppt (it expects .title and .body fields)
                text_data = struct();
                [~, name_only, ext] = fileparts(filename);
                text_data.title = [name_only ext]; % Use just filename without path
                text_data.consts = smscan.consts;

                % Safely handle comments for body text
                if isfield(scan, 'comments') && ~isempty(scan.comments)
                    if iscell(scan.comments)
                        text_data.body = strvcat(scan.comments{:});
                    elseif ischar(scan.comments)
                        text_data.body = scan.comments;
                    else
                        text_data.body = char(scan.comments);
                    end
                else
                    text_data.body = '';
                end
                
                % Validate PowerPoint file path and call smsaveppt correctly
                if isfield(smaux, 'pptsavefile') && ~isempty(smaux.pptsavefile) && ischar(smaux.pptsavefile)
                    smsaveppt(smaux.pptsavefile, text_data, '-f1000');
                end
                
            catch pptError
                % PowerPoint save failed - continue silently
            end
        end
        
        % Save data file
        if exist('filename', 'var') && ~isempty(filename)
            try
                save(filename, 'data', 'scan')
                
                % Remove temporary files created for this scan only
                [p,f,e] = fileparts(filename);
                try
                    % Create the same pattern used for temp file creation
                    if isempty(p)
                        temp_pattern = sprintf('%s-temp*%s~', f, e);
                        temp_files = dir(temp_pattern);
                        for tf = 1:length(temp_files)
                            delete(temp_files(tf).name);
                        end
                    else
                        % Use consistent path separators with creation
                        temp_pattern = sprintf('%s%s%s-temp*%s~', p, filesep, f, e);
                        temp_files = dir(temp_pattern);
                        for tf = 1:length(temp_files)
                            delete(fullfile(p, temp_files(tf).name));
                        end
                    end
                catch tempError
                    % Silent failure - don't interrupt scanning
                end
            catch ME
                % Silent failure - don't interrupt scanning
            end
        end

        save_operations_completed = true;

    end

    % Nested function for graceful window close
    function gracefulClose()
        if ishandle(figurenumber)
            % In case interrupted during or before save, ensure data is saved
            saveData();
            delete(figurenumber); % Close the figure
        end
        scan_should_exit = true;
    end

end