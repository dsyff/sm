classdef measurementScan
    % Self-contained scan description for measurementEngine.
    %
    % This object is serializable and can be sent to a worker engine.
    % It is NOT responsible for plotting, but it records plot selections so the
    % engine can decide what data to send to the client.

    properties
        name (1, 1) string = ""
        comments = []

        % Filled by measurementEngine at run time.
        startTime (1, 1) datetime = NaT
        endTime (1, 1) datetime = NaT
        duration (1, 1) duration = seconds(NaN)

        % Legacy-style constants struct array with fields:
        %   setchan (char/string), val (double), set (logical/double)
        consts (1, :) struct = struct("setchan", {}, "val", {}, "set", {})

        % Loop definitions (struct array). Required fields:
        %   npoints (double)
        %   getchan (string row/col) - VECTOR channel friendly names
        %   setchan (string row/col) - PURE scalar channel friendly names
        % Optional legacy-compatible fields preserved when present:
        %   rng, setchanranges
        loops (1, :) struct = struct([])

        % Loop index used for temp-save checks.
        saveloop (1, 1) double {mustBePositive, mustBeInteger} = 2

        % Minimum time between temp saves.
        saveMinInterval (1, 1) duration = minutes(10)

        % Display selections (legacy scan.disp struct array)
        disp (1, :) struct = struct("loop", {}, "channel", {}, "dim", {}, "name", {})

        figure (1, 1) double = NaN

        mode (1, 1) string {mustBeMember(mode, ["safe", "turbo"])} = "safe"

        % Scalar get-channel names per loop (cell array of string columns).
        scalarGetNamesByLoop (1, :) cell = cell(1, 0)

        % Scalar get-channel names in the save-data order (column).
        flatScalarGetNames (:, 1) string = string.empty(0, 1)

        % Scalar plot channel names (1 per disp entry, column).
        plotScalarNames (:, 1) string = string.empty(0, 1)
    end

    methods (Static)
        function obj = fromLegacy(scan, channelSizeFcn, mode)
            arguments
                scan (1, 1) struct
                channelSizeFcn (1, 1) function_handle
                mode (1, 1) string {mustBeMember(mode, ["safe", "turbo"])} = "safe"
            end

            if ~isfield(scan, "loops") || ~isstruct(scan.loops)
                error("measurementScan:InvalidScan", "scan.loops must be a struct array.");
            end

            obj = measurementScan();
            obj.mode = mode;

            if isfield(scan, "name")
                obj.name = string(scan.name);
            end
            if isfield(scan, "comments")
                obj.comments = scan.comments;
            end
            if isfield(scan, "figure")
                obj.figure = double(scan.figure);
            end
            if isfield(scan, "startTime")
                try
                    obj.startTime = datetime(scan.startTime);
                catch
                end
            end
            if isfield(scan, "endTime")
                try
                    obj.endTime = datetime(scan.endTime);
                catch
                end
            end
            if isfield(scan, "duration")
                try
                    d = scan.duration;
                    if isduration(d)
                        obj.duration = d;
                    else
                        obj.duration = seconds(double(d));
                    end
                catch
                end
            end

            if isfield(scan, "consts") && ~isempty(scan.consts)
                obj.consts = scan.consts;
                if ~isfield(obj.consts, "set")
                    [obj.consts.set] = deal(1);
                end
            end

            legacyLoops = scan.loops;
            nloops = numel(legacyLoops);

            % Normalize saveloop to a single loop index.
            if ~isfield(scan, "saveloop") || isempty(scan.saveloop)
                obj.saveloop = min(2, max(1, nloops));
            else
                saveLoop = double(scan.saveloop);
                if ~(isscalar(saveLoop) && isfinite(saveLoop) && saveLoop >= 1 && mod(saveLoop, 1) == 0)
                    error("measurementScan:InvalidSaveLoop", "saveloop must be a positive integer loop index.");
                end
                obj.saveloop = saveLoop;
            end

            if ~isfield(scan, "saveMinInterval") || isempty(scan.saveMinInterval)
                obj.saveMinInterval = minutes(10);
            else
                saveMinInterval = scan.saveMinInterval;
                if ~isduration(saveMinInterval)
                    saveMinInterval = seconds(double(saveMinInterval));
                end
                if ~(isscalar(saveMinInterval) && isfinite(seconds(saveMinInterval)) && saveMinInterval > seconds(0))
                    error("measurementScan:InvalidSaveMinInterval", ...
                        "saveMinInterval must be a finite, positive duration.");
                end
                obj.saveMinInterval = saveMinInterval;
            end

            obj.loops = legacyLoops;

            % Normalize loops fields and convert timing to duration.
            for loopIdx = 1:nloops
                loopDef = obj.loops(loopIdx);

                if ~isfield(loopDef, "npoints") || isempty(loopDef.npoints)
                    if isfield(loopDef, "rng") && ~isempty(loopDef.rng)
                        loopDef.npoints = numel(loopDef.rng);
                    else
                        loopDef.npoints = 101;
                    end
                end

                if ~isfield(loopDef, "getchan") || isempty(loopDef.getchan)
                    loopDef.getchan = string.empty(0, 1);
                else
                    loopDef.getchan = string(loopDef.getchan);
                    if isrow(loopDef.getchan)
                        loopDef.getchan = loopDef.getchan.';
                    end
                end

                if ~isfield(loopDef, "setchan") || isempty(loopDef.setchan)
                    loopDef.setchan = string.empty(0, 1);
                else
                    loopDef.setchan = string(loopDef.setchan);
                    if isrow(loopDef.setchan)
                        loopDef.setchan = loopDef.setchan.';
                    end
                end

                % startwait / waittime are stored as duration.
                if ~isfield(loopDef, "startwait") || isempty(loopDef.startwait)
                    loopDef.startwait = seconds(0);
                elseif ~isduration(loopDef.startwait)
                    loopDef.startwait = seconds(double(loopDef.startwait));
                end

                if ~isfield(loopDef, "waittime") || isempty(loopDef.waittime)
                    loopDef.waittime = seconds(0);
                elseif ~isduration(loopDef.waittime)
                    loopDef.waittime = seconds(double(loopDef.waittime));
                end
                % Assign updated fields back without struct replacement, to
                % avoid "dissimilar structures" errors when adding new fields.
                obj.loops(loopIdx).npoints = loopDef.npoints;
                obj.loops(loopIdx).getchan = loopDef.getchan;
                obj.loops(loopIdx).setchan = loopDef.setchan;
                obj.loops(loopIdx).startwait = loopDef.startwait;
                obj.loops(loopIdx).waittime = loopDef.waittime;
            end

            % Expand scalar get channel names for saving/plotting.
            scalarByLoop = cell(1, nloops);
            flatScalar = strings(0, 1);
            for loopIdx = 1:nloops
                getNames = obj.loops(loopIdx).getchan;
                loopScalar = strings(0, 1);
                for nameIdx = 1:numel(getNames)
                    chanName = getNames(nameIdx);
                    chanSize = channelSizeFcn(chanName);
                    if ~(isnumeric(chanSize) && isscalar(chanSize) && isfinite(chanSize) && chanSize >= 1)
                        error("measurementScan:InvalidChannelSize", "channelSizeFcn returned invalid size for %s.", chanName);
                    end
                    if chanSize > 1
                        for vecIdx = 1:chanSize
                            scalarName = chanName + "_" + vecIdx;
                            loopScalar(end+1, 1) = scalarName;
                            flatScalar(end+1, 1) = scalarName;
                        end
                    else
                        loopScalar(end+1, 1) = chanName;
                        flatScalar(end+1, 1) = chanName;
                    end
                end
                scalarByLoop{loopIdx} = loopScalar;
            end
            obj.scalarGetNamesByLoop = scalarByLoop;
            obj.flatScalarGetNames = flatScalar;

            if isfield(scan, "disp") && ~isempty(scan.disp)
                obj.disp = scan.disp;
                % Normalize disp entries so obj.disp(k).channel is a numeric scalar
                % index into flatScalarGetNames (scalar-expanded order).
                plotNames = strings(numel(obj.disp), 1);
                for dispIdx = 1:numel(obj.disp)
                    name = "";
                    if isfield(obj.disp, "name") && strlength(string(obj.disp(dispIdx).name)) > 0
                        name = string(obj.disp(dispIdx).name);
                    end

                    dc = [];
                    if isfield(obj.disp, "channel")
                        dc = obj.disp(dispIdx).channel;
                    end

                    if strlength(name) == 0 && ~isempty(dc) && (isstring(dc) || ischar(dc))
                        name = string(dc);
                    end

                    if strlength(name) > 0
                        idx = find(flatScalar == name, 1);
                        if isempty(idx)
                            error("measurementScan:InvalidDispChannel", "disp(%d) refers to unknown plot channel name %s.", dispIdx, name);
                        end
                        obj.disp(dispIdx).channel = double(idx);
                        obj.disp(dispIdx).name = name;
                        plotNames(dispIdx) = name;
                        continue;
                    end

                    if isnumeric(dc) && isscalar(dc)
                        if dc >= 1 && dc <= numel(flatScalar)
                            plotNames(dispIdx) = flatScalar(dc);
                            obj.disp(dispIdx).name = plotNames(dispIdx);
                            obj.disp(dispIdx).channel = double(dc);
                        else
                            error("measurementScan:InvalidDispChannel", "disp(%d).channel=%d is out of range (1..%d).", dispIdx, dc, numel(flatScalar));
                        end
                    end
                end
                obj.plotScalarNames = plotNames;
            end
        end
    end

    methods
        function scanStruct = toSaveStruct(obj)
            scanStruct = struct();
            scanStruct.name = char(obj.name);
            scanStruct.comments = obj.comments;
            scanStruct.startTime = obj.startTime;
            scanStruct.endTime = obj.endTime;
            scanStruct.duration = obj.duration;
            scanStruct.consts = obj.consts;
            scanStruct.saveloop = obj.saveloop;
            scanStruct.saveMinInterval = seconds(obj.saveMinInterval);
            scanStruct.disp = obj.disp;
            scanStruct.figure = obj.figure;

            loopsOut = obj.loops;
            nloops = numel(loopsOut);
            for loopIdx = 1:nloops
                loopDef = loopsOut(loopIdx);

                % Convert scalar-expanded getchan to cellstr row for compatibility.
                scalarNames = strings(0, 1);
                if loopIdx <= numel(obj.scalarGetNamesByLoop)
                    scalarNames = obj.scalarGetNamesByLoop{loopIdx};
                end

                loopDef.getchan = cellstr(scalarNames(:)).';
                loopDef.setchan = cellstr(string(loopDef.setchan(:)).');

                if isfield(loopDef, "waittime") && isduration(loopDef.waittime)
                    loopDef.waittime = seconds(loopDef.waittime);
                end
                if isfield(loopDef, "startwait") && isduration(loopDef.startwait)
                    loopDef.startwait = seconds(loopDef.startwait);
                end

                loopsOut(loopIdx) = loopDef;
            end

            scanStruct.loops = loopsOut;
        end
    end
end

