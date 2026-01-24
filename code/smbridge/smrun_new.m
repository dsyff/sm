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

smbridgeAddSharedPaths();

%flush all instrument buffers before starting scan
instrumentRackGlobal.flush();

% Track whether saveData has already persisted results, even if initialization aborts early
save_operations_completed = false;

if ~isstruct(scan)
    filename = scan;
    scan = smscan;
end

if isstruct(scan) && isfield(scan, 'ppt')
    scan = rmfield(scan, 'ppt');
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
    scan_disp = struct('loop', {}, 'channel', {}, 'dim', {});
else
    scan_disp = scan.disp;
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
getchan_scalar_names = cell(1, nloops);
setchan_scalar_names = cell(1, nloops);

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


% Handle setchanranges field from legacy GUI compatibility 
% setchanranges contains the [start, end] values for each channel
% Example: setchanranges = {[2, -5], [12, 13]} means:
%   - Channel 1 should go from 2 to -5  
%   - Channel 2 should go from 12 to 13
% We'll use a simple index-based approach where all channels are treated equally
for i=1:length(scandef)
    if isfield(scandef(i),'setchanranges') && ~isempty(scandef(i).setchanranges)
        % setchanranges detected - will be handled during scanning
    end
end

for i = 1:nloops
    % Ensure npoints is set - either from existing value or default
    if isempty(scandef(i).npoints)        
        if isfield(scandef(i), 'rng') && ~isempty(scandef(i).rng)
            scandef(i).npoints = length(scandef(i).rng);
        else
            scandef(i).npoints = 101;  % Default value if nothing is specified
        end
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

    if ~isempty(scandef(i).setchan)
        scalarSetNames = strings(1, nsetchan(i));
        for idx = 1:nsetchan(i)
            scalarSetNames(idx) = string(smdata.channels(scandef(i).setchan(idx)).name);
        end
        setchan_scalar_names{i} = scalarSetNames;
    else
        setchan_scalar_names{i} = string.empty(1, 0);
    end

    if ~isempty(scandef(i).getchan)
        scalarGetNames = strings(1, ngetchan(i));
        for idx = 1:ngetchan(i)
            scalarGetNames(idx) = string(smdata.channels(scandef(i).getchan(idx)).name);
        end
        getchan_scalar_names{i} = scalarGetNames;
    else
        getchan_scalar_names{i} = string.empty(1, 0);
    end
end

% Build getch after channel lookup conversion - fully vectorized
all_getchans = {scandef.getchan};
nonempty_mask = ~cellfun(@isempty, all_getchans);
if any(nonempty_mask)
    normalized_getchans = cellfun(@(chan) chan(:), all_getchans(nonempty_mask), 'UniformOutput', false);
    getch = vertcat(normalized_getchans{:});
else
    getch = [];
end

npoints = [scandef.npoints];
totpoints = prod(npoints);

scan_for_save_template = buildScanForSaveTemplate();

datadim = zeros(sum(ngetchan), 5);
data = cell(1, sum(ngetchan));
ndim = zeros(1, sum(ngetchan));
dataloop = zeros(1, sum(ngetchan));
disph = zeros(1, sum(ngetchan));

for i = 1:nloops
    % Pre-size using only loop dimensions; each channel sample is scalar per point
    baseDim = npoints(end:-1:i);
    if isempty(baseDim)
        baseDim = 1;
    end
    for j = 1:ngetchan(i)
        ind = sum(ngetchan(1:i-1)) + j;
        dim = baseDim;
        if length(dim) == 1
            dim(2) = 1;
        end
        data{ind} = nan(dim);
        dataloop(ind) = i;
    end
end
   
% Determine subplot layout based on number of displays
switch length(scan_disp)
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
    otherwise,      sbpl = [6 6]; scan_disp(36:end) = [];
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

if ishandle(figurenumber)
    figHandle = figure(figurenumber);
    clf(figHandle);
else
    figHandle = figure(figurenumber);
    figHandle.WindowState = 'maximized';
    % Ensure figure is fully initialized before proceeding
    drawnow;
end

set(figHandle, 'CurrentCharacter', char(0));

% Set CloseRequestFcn for graceful exit
set(figHandle, 'CloseRequestFcn', @(src,evt) gracefulClose());


% Set default display loops
if ~isfield(scan_disp, 'loop')
    for i = 1:length(scan_disp)
        scan_disp(i).loop = dataloop(scan_disp(i).channel)-1;
    end
end

s.type = '()';
s2.type = '()';
display_x_loops = zeros(1, length(scan_disp));
display_y_loops = zeros(1, length(scan_disp));
disp2d_info = repmat(struct( ...
    "x_loop", [], ...
    "y_loop", [], ...
    "x_dim", [], ...
    "y_dim", [], ...
    "x_len", [], ...
    "y_len", [], ...
    "fixed_dims", [], ...
    "fixed_loops", [], ...
    "subs_template", []), 1, length(scan_disp));
for i = 1:length(scan_disp)    
    subplot(sbpl(1), sbpl(2), i);
    dc = scan_disp(i).channel;

    baseLen = nloops - dataloop(dc) + 1 + ndim(dc);
    s.subs = num2cell(ones(1, baseLen));
    if scan_disp(i).dim > numel(s.subs)
        s.subs(end+1:scan_disp(i).dim) = {1};
    end
    idx_start = numel(s.subs) - scan_disp(i).dim + 1;
    idx_start = max(1, idx_start);
    [s.subs{idx_start:end}] = deal(':');
    
    dataSize = size(data{dc});
    if isempty(dataSize)
        dataSize = 1;
    end
    dimCount = numel(dataSize);
    loopsDesc = nloops:-1:dataloop(dc);
    loopForDim = zeros(1, dimCount);
    mapLimit = min(numel(loopsDesc), dimCount);
    if mapLimit > 0
        loopForDim(1:mapLimit) = loopsDesc(1:mapLimit);
    end
    dimForLoop = zeros(1, nloops);
    for dimIdx = 1:dimCount
        loopNumber = loopForDim(dimIdx);
        if loopNumber > 0
            dimForLoop(loopNumber) = dimIdx;
        end
    end

    channel_loop_idx = dataloop(dc);
    if channel_loop_idx < 1 || channel_loop_idx > nloops
        error("smrun_new:LoopMappingError", ...
            "Display %d maps channel %d to invalid loop index %d.", ...
            i, dc, channel_loop_idx);
    end
    if dimForLoop(channel_loop_idx) == 0
        error("smrun_new:LoopMappingError", ...
            "Display %d cannot resolve loop %d for channel %d axes.", ...
            i, channel_loop_idx, dc);
    end

    display_x_loops(i) = channel_loop_idx;
    xDim = dimForLoop(channel_loop_idx);

    xlab = '';
    if xDim > 0
        axisLength = dataSize(xDim);
        [loopAxis, loopLabel] = buildLoopAxis(channel_loop_idx);
        loopAxis = double(loopAxis(:)');
        if isempty(loopAxis)
            if axisLength > 0
                loopAxis = 1:axisLength;
            end
        elseif axisLength > 0 && numel(loopAxis) ~= axisLength
            if axisLength == 1
                loopAxis = loopAxis(1);
            else
                loopAxis = linspace(loopAxis(1), loopAxis(end), axisLength);
            end
        end
        x = loopAxis;
        xlab = loopLabel;
    else
        axisLength = dataSize(max(1, dimCount));
        if axisLength <= 0
            axisLength = 1;
        end
        x = 1:axisLength;
        xlab = 'n';
    end

    if scan_disp(i).dim == 2
        if channel_loop_idx >= nloops
            error("smrun_new:InvalidLoopConfiguration", ...
                "Display %d uses channel %d from loop %d but requires at least two varying loops (n = %d).", ...
                i, dc, channel_loop_idx, nloops);
        end

        x_loop_idx = channel_loop_idx;
        y_loop_idx = channel_loop_idx + 1;
        display_x_loops(i) = x_loop_idx;
        display_y_loops(i) = y_loop_idx;

        xDim = nloops - x_loop_idx + 1;
        yDim = nloops - y_loop_idx + 1;
        if xDim < 1 || xDim > dimCount || yDim < 1 || yDim > dimCount
            error("smrun_new:LoopMappingError", ...
                "Display %d cannot resolve axes for channel %d (x loop %d, y loop %d).", ...
                i, dc, x_loop_idx, y_loop_idx);
        end

        xAxisLength = dataSize(xDim);
        [xAxis, xLabel] = buildLoopAxis(x_loop_idx);
        xAxis = double(xAxis(:)');
        if isempty(xAxis)
            if xAxisLength > 0
                xAxis = 1:xAxisLength;
            end
        elseif xAxisLength > 0 && numel(xAxis) ~= xAxisLength
            if xAxisLength == 1
                xAxis = xAxis(1);
            else
                xAxis = linspace(xAxis(1), xAxis(end), xAxisLength);
            end
        end

        yAxisLength = dataSize(yDim);
        [yAxis, yLabel] = buildLoopAxis(y_loop_idx);
        yAxis = double(yAxis(:)');
        if isempty(yAxis)
            if yAxisLength > 0
                yAxis = 1:yAxisLength;
            end
        elseif yAxisLength > 0 && numel(yAxis) ~= yAxisLength
            if yAxisLength == 1
                yAxis = yAxis(1);
            else
                yAxis = linspace(yAxis(1), yAxis(end), yAxisLength);
            end
        end

        x = xAxis;
        y = yAxis;
        xlab = xLabel;
        ylab = yLabel;

        fixed_dims = 1:dimCount;
        fixed_dims([xDim yDim]) = [];
        fixed_loops = nloops - fixed_dims + 1;
        subs_template = repmat({1}, 1, dimCount);
        subs_template{xDim} = ':';
        subs_template{yDim} = ':';

        s.subs = subs_template;
        z = subsref(data{dc}, s);
        if numel(z) == yAxisLength * xAxisLength
            z = reshape(z, yAxisLength, xAxisLength);
        end

        disp2d_info(i).x_loop = x_loop_idx;
        disp2d_info(i).y_loop = y_loop_idx;
        disp2d_info(i).x_dim = xDim;
        disp2d_info(i).y_dim = yDim;
        disp2d_info(i).x_len = xAxisLength;
        disp2d_info(i).y_len = yAxisLength;
        disp2d_info(i).fixed_dims = fixed_dims;
        disp2d_info(i).fixed_loops = fixed_loops;
        disp2d_info(i).subs_template = subs_template;

        disph(i) = imagesc(x, y, z);

        xLimits = computeAxisLimits(x);
        yLimits = computeAxisLimits(y);
        set(gca, 'XLim', xLimits, 'YLim', yLimits, 'ydir', 'normal');
        colorbar;
        if dc <= length(getch)
            title(strrep(smdata.channels(getch(dc)).name, '_', '\_'));
        end
        xlabel(strrep(xlab, '_', '\_'));
        ylabel(strrep(ylab, '_', '\_'));
    else
        disph(i) = plot(nan, nan);
        xLimits = computeAxisLimits(x);
        set(gca, 'XLim', xLimits, 'XLimMode', 'manual');
        xlabel(strrep(xlab, '_', '\_'));
        if dc <= length(getch)
            plotLabel = strrep(smdata.channels(getch(dc)).name, '_', '\_');
            ylabel(plotLabel);
            title(plotLabel);
        else
            title('');
        end
    end
end  

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
disp_loops = [scan_disp.loop];
disp_channels = [scan_disp.channel];
disp_dims = [scan_disp.dim];

loop_to_display = cell(1, nloops);
for k = 1:numel(scan_disp)
    loop_id = disp_loops(k);
    if loop_id >= 1 && loop_id <= nloops
        loop_to_display{loop_id}(end+1) = k;
    end
end

% Pre-allocate axis arrays for all loops to avoid repeated calculations
x_axes = cell(1, nloops);
y_axes = cell(1, nloops);
x_labels = cell(1, nloops);
y_labels = cell(1, nloops);

for loop_idx = 1:nloops
    [axisVals, axisLabel] = buildLoopAxis(loop_idx);
    axisVals = double(axisVals(:)');
    x_axes{loop_idx} = axisVals;
    y_axes{loop_idx} = axisVals;
    x_labels{loop_idx} = axisLabel;
    y_labels{loop_idx} = axisLabel;
end

% Cache subplot information to avoid repeated subplot() calls
subplot_cache = containers.Map('KeyType', 'int32', 'ValueType', 'any');
for k = 1:length(scan_disp)
    subplot_cache(k) = struct('row', sbpl(1), 'col', sbpl(2), 'idx', k);
end

% Pre-compute setchanranges calculations for performance
has_setchanranges = false(1, nloops);
channel_slopes = cell(1, nloops);
channel_intercepts = cell(1, nloops);
channel_single_values = cell(1, nloops);
has_waittime = false(1, nloops);
waittime_values = zeros(1, nloops);
has_startwait = false(1, nloops);
startwait_values = zeros(1, nloops);

for j = 1:nloops
    % Pre-compute setchanranges parameters
    if isfield(scandef(j),'setchanranges') && ~isempty(scandef(j).setchanranges)
        has_setchanranges(j) = true;
        num_ranges = min(nsetchan(j), length(scandef(j).setchanranges));
        channel_slopes{j} = zeros(1, num_ranges);
        channel_intercepts{j} = zeros(1, num_ranges);
        channel_single_values{j} = zeros(1, num_ranges);
        
        for k = 1:num_ranges
            channel_range = scandef(j).setchanranges{k};
            if npoints(j) > 1
                channel_slopes{j}(k) = (channel_range(2) - channel_range(1)) / (npoints(j) - 1);
                channel_intercepts{j}(k) = channel_range(1);
            else
                channel_single_values{j}(k) = channel_range(1);
            end
        end
    end
    
    % Pre-compute timing parameters
    if isfield(scandef(j),'waittime') && ~isempty(scandef(j).waittime)
        has_waittime(j) = true;
        waittime_values(j) = scandef(j).waittime;
    end
    
    if isfield(scandef(j),'startwait') && ~isempty(scandef(j).startwait)
        has_startwait(j) = true;
        startwait_values(j) = scandef(j).startwait;
    end
end

% Pre-allocate channel value arrays for maximum channels
max_channels = max(nsetchan);
if max_channels > 0
    val_for_channels_buffer = zeros(1, max_channels);
end

% Cache figure handle checks
scan_should_exit = false;
temp_file_counter = 0;
figure_check_counter = 0;
figure_check_interval = 10;  % Check figure every 10 points

% Find dummy loops
isdummy = false(1, nloops);
for i = 1:nloops
    isdummy(i) = isfield(scandef(i), 'waittime') && ~isempty(scandef(i).waittime) && scandef(i).waittime < 0 ...
        && isempty(scandef(i).getchan) ...
        && ~any(scan.saveloop(1) == i) && ~any([scan_disp.loop] == i);
end

% main loop - optimized version
for point_idx = 1:totpoints_cached    
    % Optimized loop selection logic
    if point_idx > 1
        loops_end_idx = find(count > 1, 1, 'first');
        if isempty(loops_end_idx)
            loops_end_idx = nloops_cached;
        end
        loops = 1:loops_end_idx;
    else
        loops = 1:nloops_cached;
    end       
    
    % Set channels - optimized with pre-computed values
    active_loops = loops(~isdummy(loops) | count(loops)==1);
    for j = fliplr(active_loops)
        % Fast channel value calculation using pre-computed parameters
        if has_setchanranges(j)
            if npoints(j) > 1
                % Vectorized calculation using pre-computed slopes and intercepts
                num_ranges = length(channel_slopes{j});
                if nsetchan(j) > 0
                    val_for_channels_buffer(1:num_ranges) = channel_intercepts{j} + ...
                        channel_slopes{j} * (count(j) - 1);
                    val_for_channels = val_for_channels_buffer(1:nsetchan(j));
                end
            else
                val_for_channels = channel_single_values{j}(1:nsetchan(j));
            end
        else
            % Simple case: all channels get the same count value
            if nsetchan(j) > 0
                val_for_channels = repmat(count(j), 1, nsetchan(j));
            end
        end

        % Instrument communication with cached strings
        if count(j) == 1
            if nsetchan(j) > 0 && ~isempty(setchan_strings{j})
                instrumentRackGlobal.rackSet(setchan_strings{j}, val_for_channels);
                
                if has_startwait(j)
                    pause(startwait_values(j));
                end
            end
            tloop(j) = now;
        else
            if nsetchan(j) > 0 && ~isempty(setchan_strings{j})
                instrumentRackGlobal.rackSet(setchan_strings{j}, val_for_channels);
            end
        end

        % Optimized wait time handling
        if has_waittime(j)
            pause(waittime_values(j));
        end
    end
    
    % Optimized loop determination for reading
    if point_idx > 1
        loops_end_idx = find(count < npoints, 1, 'first');
        if isempty(loops_end_idx)
            loops = 1:nloops_cached;
        else
            loops = 1:loops_end_idx;
        end
    end
    
    % Read data - optimized with pre-computed offsets
    active_read_loops = loops(~isdummy(loops));
    for j = active_read_loops
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
        loopDisplayIndices = [];
        if j <= numel(loop_to_display) && ~isempty(loop_to_display{j})
            loopDisplayIndices = loop_to_display{j};
        end

        for dispIdx = loopDisplayIndices
            k = dispIdx;
            dc = disp_channels(k);

            if ~ishandle(disph(k)) || ~ishandle(figHandle)
                continue;
            end
                
            % For display updates, we want to show only data collected so far
            % Create subscript for extracting current data state
            if disp_dims(k) == 2
                info = disp2d_info(k);
                if isempty(info.x_dim)
                    continue;
                end
                s2.subs = info.subs_template;
                if ~isempty(info.fixed_dims)
                    for idx = 1:numel(info.fixed_dims)
                        loop_idx = info.fixed_loops(idx);
                        if loop_idx >= 1 && loop_idx <= numel(count)
                            s2.subs{info.fixed_dims(idx)} = count(loop_idx);
                        end
                    end
                end
                
            else
                % For 1D displays, extract based on current loop position
                nind = ndim(dc) + nloops + 1 - dataloop(dc) - disp_dims(k);
                s2.subs = [num2cell([count(end:-1:max(j, end-nind+1)), ones(1, max(0, nind+j-1-nloops))]),...
                    repmat({':'},1, disp_dims(k))];
            end
            
            try
                if disp_dims(k) == 2
                    % Only update 2D plots after a full x-loop line completes
                    innerLoopIdx = info.x_loop;
                    if innerLoopIdx <= numel(count) && innerLoopIdx <= numel(npoints)
                        if count(innerLoopIdx) ~= npoints(innerLoopIdx)
                            continue;
                        end
                    end

                    z_data = subsref(data{dc}, s2);
                    if numel(z_data) == info.y_len * info.x_len
                        z_data = reshape(z_data, info.y_len, info.x_len);
                    end
                    set(disph(k), 'cdata', z_data);
                else                
                    y_data = subsref(data{dc}, s2);
                    % For 3D+ scans, reset inner-loop plots when the outermost loop changes
                    if nloops > 2 && j == nloops && dataloop(dc) < nloops
                        y_data(:) = NaN;  % Clear the plot
                    end

                    y_vec = y_data(:)';
                    x_vec = [];
                    loopCandidate = display_x_loops(k);
                    if loopCandidate >= 1 && loopCandidate <= numel(x_axes)
                        candidate_x = x_axes{loopCandidate};
                        if ~isempty(candidate_x)
                            candidate_x = candidate_x(:)';
                            if numel(candidate_x) == numel(y_vec)
                                x_vec = candidate_x;
                            elseif numel(candidate_x) >= 2 && numel(y_vec) > 1
                                x_vec = linspace(candidate_x(1), candidate_x(end), numel(y_vec));
                            end
                        end
                    end
                    if isempty(x_vec)
                        x_vec = 1:numel(y_vec);
                    end

                    set(disph(k), 'XData', x_vec, 'YData', y_vec);
                end
            catch ME
                saveData();  % Ensure data is saved before exiting
                rethrow(ME);
            end
        end
        
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %drawnow limitrate;
        drawnow;

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
                saveScanDataToFile(tempfile);
            catch tempSaveError
                fprintf("smrun_new: Failed to save temporary data to %s (%s).\n", char(tempfile), tempSaveError.message);
                % Fallback save
                try
                    [~,f,e] = fileparts(filename);
                    fallbackFile = sprintf('%s_fallback%s', f, e);
                    saveScanDataToFile(fallbackFile);
                catch fallbackSaveError
                    fprintf("smrun_new: Fallback save failed for %s (%s).\n", char(fallbackFile), fallbackSaveError.message);
                end
            end
        end
               
    end
    
    % Update counters properly for nested loops
    j = 1;
    while j <= length(loops)
        if count(loops(j)) < npoints(loops(j))
            count(loops(j)) = count(loops(j)) + 1;
            break;
        else
            count(loops(j)) = 1;
            j = j + 1;
        end
    end
    
    % Optimized exit/pause checks - only check periodically to reduce overhead
    if ishandle(figHandle)
        current_char = get(figHandle, 'CurrentCharacter');
        if current_char == char(27)  % Escape key
            set(figHandle, 'CurrentCharacter', char(0));
            saveData();
            return;
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

    prevWarningState = warning;
    warningCleanup = onCleanup(@() warning(prevWarningState)); %#ok<NASGU>
    [figpath, figname] = fileparts(filename);
    if isempty(figname)
        figstring = filename;
    elseif isempty(figpath)
        figstring = figname;
    else
        figstring = fullfile(figpath, figname);
    end
    warning('off', 'all');
    set(figHandle, 'CloseRequestFcn', 'closereq');

    try
        saveScanDataToFile(filename);
        [p,f,e] = fileparts(filename);
        try
            if isempty(p)
                temp_pattern = sprintf('%s-temp*%s~', f, e);
                temp_files = dir(temp_pattern);
                for tf = 1:length(temp_files)
                    delete(temp_files(tf).name);
                end
            else
                temp_pattern = sprintf('%s%s%s-temp*%s~', p, filesep, f, e);
                temp_files = dir(temp_pattern);
                for tf = 1:length(temp_files)
                    delete(fullfile(p, temp_files(tf).name));
                end
            end
        catch tempCleanupError
            fprintf("smrun_new: Failed to remove temp files matching %s (%s).\n", char(temp_pattern), tempCleanupError.message);
        end
    catch finalSaveError
        fprintf("smrun_new: Failed to save final data (%s).\n", finalSaveError.message);
    end

    % Save PNG for figure and PowerPoint
    pngFile = sprintf("%s.png", figstring);
    png_saved = true;
    try
        if verLessThan('matlab', '25.1') % Padding name-value starts in R2025a
            exportgraphics(figHandle, pngFile, Resolution = 300);
        else
            exportgraphics(figHandle, pngFile, Resolution = 300, Padding = "tight");
        end
    catch pngError
        png_saved = false;
        fprintf("smrun_new: Failed to export PNG (%s).\n", pngError.message);
    end

    % Save PowerPoint if enabled
    try
        [pptEnabled, pptFile] = smpptGetState();
        if pptEnabled
            if isempty(pptFile)
                fprintf("smrun_new: PowerPoint append skipped (no file specified).\n");
            elseif ~png_saved
                fprintf("smrun_new: PowerPoint append skipped (PNG export failed).\n");
            else
                % Create text structure for smsaveppt_new (it expects .title and .body fields)
                text_data = struct();
                [~, name_only, ext] = fileparts(filename);
                text_data.title = [name_only ext]; % Use just filename without path
                if isfield(scan, 'consts')
                    text_data.consts = scan.consts;
                else
                    text_data.consts = [];
                end

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

                % Resolve PPT file path
                if ~isempty(pptFile)
                    % If path is relative, try to resolve using bridge.experimentRootPath
                    [pptPath, pptName, pptExt] = fileparts(pptFile);
                    if isempty(pptPath)
                        global bridge;
                        if ~isempty(bridge) && isprop(bridge, 'experimentRootPath') && ~isempty(bridge.experimentRootPath)
                            pptFile = fullfile(bridge.experimentRootPath, [pptName pptExt]);
                        end
                    end
                end

                text_data.imagePath = pngFile;
                smsaveppt_new(pptFile, text_data);
            end
        end
    catch pptError
        fprintf("smrun_new: Skipping PowerPoint append (%s).\n", pptError.message);
    end

%     try
%         pdfFile = sprintf('%s.pdf', figstring);
%         exportgraphics(figHandle, pdfFile, 'ContentType', 'vector');
%     catch pdfError
%         fprintf("smrun_new: Failed to export PDF (%s).\n", pdfError.message);
%     end

    try
        savefig(figHandle, figstring);
    catch figureSaveError
        fprintf("smrun_new: Failed to save figure (%s).\n", figureSaveError.message);
        rethrow(figureSaveError);
    end

    save_operations_completed = true;

end

% Nested function for graceful window close
function gracefulClose()
    try
        if ~ishandle(figHandle)
            return;
        end
        selection = questdlg("Stop the scan and close this figure?", "Closing", "Stop", "Cancel", "Cancel");
        if selection ~= "Stop"
            return;
        end
        if ishandle(figHandle)
            saveData();
        end
        scan_should_exit = true;
    catch closeError
        fprintf("smrun_new: gracefulClose encountered an error (%s). Once you are sure data is saved, try delete(gcf) to force close.\n", closeError.message);
    end
    if ishandle(figHandle)
        delete(figHandle);
    end
end


function saveScanDataToFile(targetFilename)
    savePayload = struct();
    savePayload.data = data;
    savePayload.scan = prepareScanForSave();
    save(targetFilename, '-struct', 'savePayload');
end


function scanStruct = prepareScanForSave()
    scanStruct = scan_for_save_template;
end


function scanStruct = buildScanForSaveTemplate()
    scanStruct = scan;
    if isfield(scanStruct, 'ppt')
        scanStruct = rmfield(scanStruct, 'ppt');
    end
    scanStruct.loops = scandef;
    for loopIdx = 1:nloops
        if isfield(scanStruct.loops(loopIdx), 'getchan')
            scalarNames = getchan_scalar_names{loopIdx};
            if isempty(scalarNames)
                scanStruct.loops(loopIdx).getchan = {};
            else
                scanStruct.loops(loopIdx).getchan = cellstr(scalarNames(:)).';
            end
        end
        if isfield(scanStruct.loops(loopIdx), 'setchan')
            scalarNames = setchan_scalar_names{loopIdx};
            if isempty(scalarNames)
                scanStruct.loops(loopIdx).setchan = {};
            else
                scanStruct.loops(loopIdx).setchan = cellstr(scalarNames(:)).';
            end
        end
    end
end


function [axisValues, axisLabel] = buildLoopAxis(loopIdx)
    axisValues = [];
    axisLabel = '';
    if ~(loopIdx >= 1 && loopIdx <= nloops)
        return;
    end

    totalPoints = npoints(loopIdx);
    loopDef = scandef(loopIdx);

    if totalPoints > 0
        if isfield(loopDef, 'setchanranges') && ~isempty(loopDef.setchanranges)
            firstRange = loopDef.setchanranges{1};
            if numel(firstRange) >= 2 && totalPoints > 1
                axisValues = linspace(firstRange(1), firstRange(2), totalPoints);
            elseif ~isempty(firstRange)
                singleValue = firstRange(1);
                axisValues = repmat(singleValue, 1, totalPoints);
            end
        end

        if isempty(axisValues)
            axisValues = 1:totalPoints;
        end
    else
        axisValues = [];
    end

    axisValues = double(axisValues(:)');

    if isfield(loopDef, 'setchan') && ~isempty(loopDef.setchan)
        chanIdx = loopDef.setchan(1);
        if chanIdx >= 1 && chanIdx <= numel(smdata.channels)
            axisLabel = smdata.channels(chanIdx).name;
        end
    end
end


function limits = computeAxisLimits(axisValues)
    axisValues = double(axisValues(:));
    if isempty(axisValues)
        limits = [0 1];
    else
        minVal = min(axisValues);
        maxVal = max(axisValues);
        if minVal == maxVal
            delta = max(abs(minVal) * 0.05, 1);
            if delta == 0
                delta = 1;
            end
            limits = [minVal - delta, maxVal + delta];
        else
            limits = [minVal, maxVal];
        end
    end
end


end