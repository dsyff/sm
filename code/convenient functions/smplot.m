function smplot(filename, varargin)
% SMPLOT - Recreate plots from saved smrun_new data files
% 
% Usage:
%   smplot(filename)              - Plot with default settings
%   smplot(filename, 'figure', N) - Use specific figure number
%   smplot(filename, 'disp', D)   - Override display configuration
%
% Inputs:
%   filename - Path to .mat file saved by smrun_new
%   varargin - Optional parameter/value pairs:
%     'figure' - Figure number to use (default: 2000)
%     'disp'   - Display configuration structure to override scan.disp
%
% Example:
%   smplot('021_scan_fast.mat')
%   smplot('data.mat', 'figure', 100)

global smdata;

% Parse input arguments
p = inputParser;
addRequired(p, 'filename', @ischar);
addParameter(p, 'figure', 2000, @isnumeric);
addParameter(p, 'disp', [], @isstruct);
parse(p, filename, varargin{:});

figurenumber = p.Results.figure;
override_disp = p.Results.disp;

% Load the data file
if ~exist(filename, 'file')
    error('File %s does not exist', filename);
end

try
    loaded_data = load(filename);
catch ME
    error('Failed to load file %s: %s', filename, ME.message);
end

% Extract required variables
if ~isfield(loaded_data, 'scan')
    error('File does not contain scan structure');
end
if ~isfield(loaded_data, 'data')
    error('File does not contain data');
end

scan = loaded_data.scan;
data = loaded_data.data;

% Use override display if provided, otherwise use scan.disp
if ~isempty(override_disp)
    disp = override_disp;
elseif isfield(scan, 'disp') && ~isempty(scan.disp)
    disp = scan.disp;
else
    % Create default display for all channels
    disp = struct('loop', {}, 'channel', {}, 'dim', {});
    num_channels = length(data);
    for i = 1:num_channels
        disp(i).channel = i;
        disp(i).dim = 1;  % Default to 1D plots
        disp(i).loop = 1; % Default to first loop
    end
end

% Validate that we have smdata for channel information
if isempty(smdata) || ~isfield(smdata, 'channels')
    warning('smdata not available - channel names will be generic');
    channel_names_available = false;
else
    channel_names_available = true;
end

% Extract scan parameters
scandef = scan.loops;
nloops = length(scandef);

% Initialize arrays similar to smrun_new
npoints = [scandef.npoints];
ngetchan = zeros(1, nloops);
datadim = zeros(length(data), 5);
ndim = zeros(1, length(data));
dataloop = zeros(1, length(data));

% Build getch for channel information (if available)
if channel_names_available
    all_getchans = {scandef.getchan};
    nonempty_mask = ~cellfun(@isempty, all_getchans);
    if any(nonempty_mask)
        getch = vertcat(all_getchans{nonempty_mask});
    else
        getch = [];
    end
else
    getch = [];
end

% Calculate channel counts per loop
for i = 1:nloops
    if isfield(scandef(i), 'getchan')
        ngetchan(i) = length(scandef(i).getchan);
    else
        ngetchan(i) = 0;
    end
end

% Determine data dimensions and loop associations
for i = 1:length(data)
    if ~isempty(data{i})
        data_size = size(data{i});
        
        % Find which loop this data belongs to
        cumulative_channels = cumsum(ngetchan);
        dataloop(i) = find(i <= cumulative_channels, 1);
        
        % Determine data dimensions
        if length(data_size) <= 2 && all(data_size <= max(npoints))
            ndim(i) = 0;  % Scalar data
        else
            % Find last dimension > 1 that's not a scan dimension
            scan_dims = length(npoints) - dataloop(i) + 1;
            if length(data_size) > scan_dims
                remaining_dims = data_size(scan_dims+1:end);
                ndim(i) = find(remaining_dims > 1, 1, 'last');
                if isempty(ndim(i))
                    ndim(i) = 0;
                else
                    datadim(i, 1:ndim(i)) = remaining_dims(1:ndim(i));
                end
            else
                ndim(i) = 0;
            end
        end
    end
end

% Set default display loops if not specified
if ~isfield(disp, 'loop')
    for i = 1:length(disp)
        if disp(i).channel <= length(dataloop)
            disp(i).loop = max(1, dataloop(disp(i).channel) - 1);
        else
            disp(i).loop = 1;
        end
    end
end

% Determine subplot layout
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

% Create or clear figure
if ~ishandle(figurenumber)
    figureHandle = figure(figurenumber);
    figureHandle.WindowState = 'maximized';
else
    figure(figurenumber);
    clf;
end

% Add title with filename
[~, fname, ext] = fileparts(filename);
sgtitle(sprintf('Data from: %s%s', fname, ext), 'Interpreter', 'none');

% Create plots
s.type = '()';
for i = 1:length(disp)
    if disp(i).channel > length(data)
        warning('Display channel %d exceeds available data channels (%d)', ...
            disp(i).channel, length(data));
        continue;
    end
    
    subplot(sbpl(1), sbpl(2), i);
    dc = disp(i).channel;
    
    if isempty(data{dc})
        title(sprintf('Channel %d (No Data)', dc));
        continue;
    end
    
    % Build subsref structure for data extraction
    s.subs = num2cell(ones(1, nloops - dataloop(dc) + 1 + ndim(dc)));
    [s.subs{end-disp(i).dim+1:end}] = deal(':');
    
    % Determine x-axis
    if dataloop(dc) - ndim(dc) < 1 
        if ndim(dc) > 0
            x = 1:datadim(dc, ndim(dc));
        else
            x = 1:size(data{dc}, end);
        end
        xlab = 'n';
    else
        loop_idx = dataloop(dc) - ndim(dc);
        if loop_idx <= length(scandef) && isfield(scandef(loop_idx), 'rng')
            x = scandef(loop_idx).rng;
        else
            x = 1:npoints(loop_idx);
        end
        
        % Get x-axis label
        if channel_names_available && loop_idx <= length(scandef) && ...
           isfield(scandef(loop_idx), 'setchan') && ~isempty(scandef(loop_idx).setchan)
            try
                xlab = smdata.channels(scandef(loop_idx).setchan(1)).name;
            catch
                xlab = sprintf('Loop %d', loop_idx);
            end
        else
            xlab = sprintf('Loop %d', loop_idx);
        end
    end

    % Create plot based on dimension
    if disp(i).dim == 2        
        % 2D plot (imagesc)
        if dataloop(dc) - ndim(dc) < 0
            if ndim(dc) > 1
                y = 1:datadim(dc, ndim(dc)-1);
            else
                y = 1:size(data{dc}, end-1);
            end
            ylab = 'n';
        else
            loop_idx = dataloop(dc) - ndim(dc) + 1;
            if loop_idx <= length(scandef) && isfield(scandef(loop_idx), 'rng')
                y = scandef(loop_idx).rng;
            else
                y = 1:npoints(loop_idx);
            end
            
            % Get y-axis label
            if channel_names_available && loop_idx <= length(scandef) && ...
               isfield(scandef(loop_idx), 'setchan') && ~isempty(scandef(loop_idx).setchan)
                try
                    ylab = smdata.channels(scandef(loop_idx).setchan(1)).name;
                catch
                    ylab = sprintf('Loop %d', loop_idx);
                end
            else
                ylab = sprintf('Loop %d', loop_idx);
            end
        end
        
        try
            z = subsref(data{dc}, s);
            imagesc(x, y, z);
            set(gca, 'ydir', 'normal');
            colorbar;
            xlabel(strrep(xlab, '_', '\_'));
            ylabel(strrep(ylab, '_', '\_'));
        catch ME
            plot(1, 1, 'r*');
            title(sprintf('Channel %d (Plot Error)', dc));
            warning('Error plotting 2D data for channel %d: %s', dc, ME.message);
        end
    else
        % 1D plot
        try
            y = subsref(data{dc}, s);
            plot(x, y);
            xlim(sort(x([1, end])));
            xlabel(strrep(xlab, '_', '\_'));
        catch ME
            plot(1, 1, 'r*');
            warning('Error plotting 1D data for channel %d: %s', dc, ME.message);
        end
    end
    
    % Set title (channel name if available)
    if channel_names_available && dc <= length(getch) && getch(dc) <= length(smdata.channels)
        try
            title(strrep(smdata.channels(getch(dc)).name, '_', '\_'));
        catch
            title(sprintf('Channel %d', dc));
        end
    else
        title(sprintf('Channel %d', dc));
    end
end

% Display scan information if available
if isfield(scan, 'comments') && ~isempty(scan.comments)
    if iscell(scan.comments)
        comment_str = strjoin(scan.comments, '; ');
    else
        comment_str = char(scan.comments);
    end
    fprintf('Scan comments: %s\n', comment_str);
end

fprintf('Plot created from: %s\n', filename);

end
