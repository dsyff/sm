function smeditrack(varargin)
    global engine

    smbridgeAddSharedPaths();
    smbridgeUpdateEditRackMenuState();

    rootKey = "smeditrackFigureHandle";
    existing = [];
    if isappdata(0, rootKey)
        existing = getappdata(0, rootKey);
        if ~isgraphics(existing)
            existing = [];
            rmappdata(0, rootKey);
        end
    end

    if ~exist("engine", "var") || isempty(engine) || ~isa(engine, "measurementEngine")
        notifyInfo("measurementEngine not found. Please run smready(...) first.", "Edit Rack", existing);
        return;
    end
    if engine.isScanInProgress
        notifyInfo("Edit Rack is unavailable while a scan is running.", "Edit Rack", existing);
        return;
    end

    if ~isempty(existing)
        try
            existing.Visible = "on";
        catch
        end
        reloadFcn = getappdata(existing, "smeditrackReloadFcn");
        if isa(reloadFcn, "function_handle")
            try
                reloadFcn();
            catch ME
                notifyInfo(ME.message, "Edit Rack", existing);
            end
        end
        return;
    end

    fig = uifigure( ...
        "Name", "Edit Rack", ...
        "Position", [200, 200, 1180, 520], ...
        "CloseRequestFcn", @onCloseRequest);
    setappdata(0, rootKey, fig);

    columnNames = {"Instrument", "Channel", "Ramp Rates", "Ramp Thresholds", "Software Mins", "Software Maxs"};
    tableHandle = uitable(fig, ...
        "Position", [20, 88, 1140, 412], ...
        "Data", cell(0, 6), ...
        "ColumnName", columnNames, ...
        "ColumnEditable", [false, false, true, true, true, true], ...
        "CellEditCallback", @onCellEdit);

    statusHandle = uilabel(fig, ...
        "Position", [20, 54, 700, 22], ...
        "Text", "Edits are local until Apply.");
    uibutton(fig, ...
        "Position", [760, 22, 120, 34], ...
        "Text", "Reload", ...
        "ButtonPushedFcn", @onReload);
    uibutton(fig, ...
        "Position", [900, 22, 120, 34], ...
        "Text", "Apply", ...
        "ButtonPushedFcn", @onApply);
    uibutton(fig, ...
        "Position", [1040, 22, 120, 34], ...
        "Text", "Close", ...
        "ButtonPushedFcn", @onCloseRequest);

    setappdata(fig, "smeditrackReloadFcn", @loadFromEngine);
    loadFromEngine();

    function onReload(~, ~)
        if engine.isScanInProgress
            notifyInfo("Reload is unavailable while a scan is running.", "Edit Rack", fig);
            return;
        end
        try
            loadFromEngine();
        catch ME
            notifyInfo(ME.message, "Edit Rack", fig);
        end
    end

    function loadFromEngine()
        info = engine.getRackInfoForEditing();
        rowCount = height(info);
        tableData = cell(rowCount, 6);
        for row = 1:rowCount
            tableData{row, 1} = char(string(info.instrumentFriendlyName(row)));
            tableData{row, 2} = char(string(info.channelFriendlyName(row)));
            tableData{row, 3} = formatVector(info.rampRates{row});
            tableData{row, 4} = formatVector(info.rampThresholds{row});
            tableData{row, 5} = formatVector(info.softwareMins{row});
            tableData{row, 6} = formatVector(info.softwareMaxs{row});
        end
        set(tableHandle, "Data", tableData);
        setappdata(fig, "baselineData", tableData);
        setappdata(fig, "channelSizes", double(info.channelSize(:)));
        statusHandle.Text = "Edits are local until Apply.";
    end

    function onCellEdit(src, eventData)
        if isempty(eventData) || ~isfield(eventData, "Indices") || numel(eventData.Indices) < 2
            return;
        end
        row = eventData.Indices(1);
        col = eventData.Indices(2);
        if col < 3 || col > 6
            return;
        end
        channelSizes = getappdata(fig, "channelSizes");
        if isempty(channelSizes) || row < 1 || row > numel(channelSizes)
            return;
        end

        tableData = get(src, "Data");
        instrumentName = string(tableData{row, 1});
        channelName = string(tableData{row, 2});
        fieldNames = ["rampRates", "rampThresholds", "softwareMins", "softwareMaxs"];
        fieldName = fieldNames(col - 2);
        expectedSize = double(channelSizes(row));

        try
            edited = parseVectorCell(eventData.NewData, instrumentName, channelName, fieldName);
            validateSizeCompliance(edited, expectedSize, instrumentName, channelName, fieldName);
        catch ME
            tableData{row, col} = eventData.PreviousData;
            set(src, "Data", tableData);
            notifyInfo(ME.message, "Edit Rack", fig);
        end
    end

    function onApply(~, ~)
        smbridgeUpdateEditRackMenuState();
        if engine.isScanInProgress
            notifyInfo("Cannot apply rack edits while a scan is in progress.", "Edit Rack", fig);
            return;
        end

        tableData = get(tableHandle, "Data");
        baselineData = getappdata(fig, "baselineData");
        channelSizes = getappdata(fig, "channelSizes");
        if isempty(tableData) || isempty(baselineData) || isempty(channelSizes)
            return;
        end

        rowCount = min([size(tableData, 1), size(baselineData, 1), numel(channelSizes)]);
        dirtyRows = false(rowCount, 1);
        for row = 1:rowCount
            dirtyRows(row) = ~isequal(tableData(row, 3:6), baselineData(row, 3:6));
        end
        rowIndices = find(dirtyRows);
        if isempty(rowIndices)
            notifyInfo("No changed rows to apply.", "Edit Rack", fig);
            return;
        end

        entries = table( ...
            Size = [numel(rowIndices), 5], ...
            VariableTypes = ["string", "cell", "cell", "cell", "cell"], ...
            VariableNames = ["channelFriendlyName", "rampRates", "rampThresholds", "softwareMins", "softwareMaxs"]);

        try
            for i = 1:numel(rowIndices)
                row = rowIndices(i);
                instrumentName = string(tableData{row, 1});
                channelName = string(tableData{row, 2});
                expectedSize = double(channelSizes(row));

                rampRates = parseVectorCell(tableData{row, 3}, instrumentName, channelName, "rampRates");
                rampThresholds = parseVectorCell(tableData{row, 4}, instrumentName, channelName, "rampThresholds");
                softwareMins = parseVectorCell(tableData{row, 5}, instrumentName, channelName, "softwareMins");
                softwareMaxs = parseVectorCell(tableData{row, 6}, instrumentName, channelName, "softwareMaxs");

                validateSizeCompliance(rampRates, expectedSize, instrumentName, channelName, "rampRates");
                validateSizeCompliance(rampThresholds, expectedSize, instrumentName, channelName, "rampThresholds");
                validateSizeCompliance(softwareMins, expectedSize, instrumentName, channelName, "softwareMins");
                validateSizeCompliance(softwareMaxs, expectedSize, instrumentName, channelName, "softwareMaxs");

                entries.channelFriendlyName(i) = channelName;
                entries.rampRates{i} = rampRates;
                entries.rampThresholds{i} = rampThresholds;
                entries.softwareMins{i} = softwareMins;
                entries.softwareMaxs{i} = softwareMaxs;
            end

            patch = instrumentRackEditPatch(entries);
            engine.applyRackEditPatch(patch);
            loadFromEngine();
            statusHandle.Text = sprintf("Applied %d row(s).", numel(rowIndices));
        catch ME
            notifyInfo(ME.message, "Edit Rack Apply Error", fig);
        end
    end

    function values = parseVectorCell(raw, instrumentName, channelName, fieldName)
        if isnumeric(raw)
            parsed = raw;
        elseif isstring(raw) || ischar(raw)
            txt = strtrim(char(string(raw)));
            if isempty(txt)
                error("smeditrack:InvalidValue", ...
                    "Instrument %s channel %s %s cannot be empty.", instrumentName, channelName, fieldName);
            end
            parsed = str2num(txt); %#ok<ST2NM>
        else
            error("smeditrack:InvalidValue", ...
                "Instrument %s channel %s %s must be numeric text.", instrumentName, channelName, fieldName);
        end
        if ~(isnumeric(parsed) && isvector(parsed) && isreal(parsed))
            error("smeditrack:InvalidValue", ...
                "Instrument %s channel %s %s must be a real numeric vector.", instrumentName, channelName, fieldName);
        end
        values = double(parsed(:));
        if isempty(values) || any(isnan(values))
            error("smeditrack:InvalidValue", ...
                "Instrument %s channel %s %s cannot be empty or NaN.", instrumentName, channelName, fieldName);
        end
    end

    function validateSizeCompliance(values, expectedSize, instrumentName, channelName, fieldName)
        if isscalar(values) || numel(values) == expectedSize
            return;
        end
        error("smeditrack:InvalidSize", ...
            "Instrument %s channel %s %s must be scalar or length %d.", ...
            instrumentName, channelName, fieldName, expectedSize);
    end

    function txt = formatVector(v)
        txt = char(strtrim(sprintf("%g ", double(v(:).'))));
        if isempty(txt)
            txt = "[]";
        end
        txt = char(txt);
    end

    function notifyInfo(message, titleText, parentFig)
        message = string(message);
        titleText = string(titleText);
        experimentContext.print(message);

        if nargin >= 3 && ~isempty(parentFig) && isgraphics(parentFig)
            uialert(parentFig, message, titleText, Icon = "info");
            return;
        end

        host = uifigure("Visible", "off", "Position", [100, 100, 20, 20]);
        dlg = uialert(host, message, titleText, Icon = "info");
        dlg.CloseFcn = @(~, ~) delete(host);
        host.Visible = "on";
    end

    function onCloseRequest(~, ~)
        if isappdata(0, rootKey)
            rmappdata(0, rootKey);
        end
        if isgraphics(fig)
            delete(fig);
        end
    end
end
