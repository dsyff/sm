function saveFinal_(obj, filename, scanForSave, data, figHandle)
    arguments
        obj
        filename (1, 1) string {mustBeNonzeroLengthText}
        scanForSave (1, 1) struct
        data (1, :) cell
        figHandle = []
    end
    if isempty(figHandle) || ~ishandle(figHandle)
        try
            figHandle = gcf;
        catch
            figHandle = [];
        end
    end
    closeDialogShown = false;
    if ~isempty(figHandle) && ishandle(figHandle)
        set(figHandle, "CloseRequestFcn", @onCloseWhileSaving);
    end

    savePayload = struct();
    savePayload.scan = scanForSave;
    savePayload.data = data;
    save(filename, "-struct", "savePayload");
    try
        [scanPath, scanName] = fileparts(filename);
        scanFile = fullfile(scanPath, scanName + "_scan.mat");
        scanPayload = struct();
        scanPayload.scan = scanForSave;
        save(scanFile, "-struct", "scanPayload");
    catch
    end
    try
        tempFile = filename + "~";
        if isfile(tempFile)
            delete(tempFile);
        end
    catch
    end

    % PNG + PPT + FIG mirror legacy smrun behavior.
    if isempty(figHandle) || ~ishandle(figHandle)
        return;
    end

    [figpath, figname] = fileparts(filename);
    if isempty(figname)
        figstring = filename;
    elseif isempty(figpath)
        figstring = figname;
    else
        figstring = fullfile(figpath, figname);
    end

    exportFig = figHandle;
    useExportCopy = false;
    try
        exportFig = figure(Visible = "off");
        useExportCopy = true;
        copyobj(figHandle.Children, exportFig);
        try
            exportFig.Colormap = figHandle.Colormap;
        catch
        end
        try
            ax = findall(exportFig, "Type", "axes");
            for axIdx = 1:numel(ax)
                try
                    if isprop(ax(axIdx), "Toolbar") && ~isempty(ax(axIdx).Toolbar)
                        ax(axIdx).Toolbar.Visible = "off";
                    end
                catch
                end
                try
                    disableDefaultInteractivity(ax(axIdx));
                catch
                end
            end
        catch
        end
    catch
        if useExportCopy && ~isempty(exportFig) && ishandle(exportFig)
            delete(exportFig);
        end
        exportFig = figHandle;
        useExportCopy = false;
    end

    pngFile = sprintf("%s.png", figstring);
    png_saved = true;
    forcePptSlideWidth = false;
    pptEnabled = false;
    pptFile = "";
    try
        [pptEnabled, pptFile] = smpptGetState();
    catch
    end
    try
        if ~isMATLABReleaseOlderThan("R2025a") && pptEnabled
            % Export at a fixed pixel size for PPT. Width is fixed; height is
            % slightly taller so the inserted image fills more of the slide.
            exportWidthPx = 2560;
            exportHeightPx = 1300;
            try
                exportFig.Units = "pixels";
                exportFig.Position(3:4) = [exportWidthPx, exportHeightPx];
            catch
            end
            exportgraphics(exportFig, pngFile, ...
                Units = "pixels", Width = exportWidthPx, Height = exportHeightPx, ...
                Padding = "tight", PreserveAspectRatio = "on");
        elseif isMATLABReleaseOlderThan("R2025a")
            exportFig.Visible = "on";
            exportFig.WindowState = "maximized";
            drawnow;
            forcePptSlideWidth = true;
            exportgraphics(exportFig, pngFile);
        else
            exportgraphics(exportFig, pngFile, Resolution = 300, Padding = "tight");
        end
    catch
        png_saved = false;
    end

    % Save PowerPoint if enabled
    try
        if pptEnabled
            pptFile = string(pptFile);
            if strlength(pptFile) == 0
                % no file
            elseif ~png_saved
                % no png
            else
                text_data = struct();
                [~, name_only, ext] = fileparts(filename);
                text_data.title = char(name_only + ext);
                headerLines = strings(0, 1);
                if isfield(scanForSave, "duration") && isduration(scanForSave.duration) && isfinite(seconds(scanForSave.duration))
                    headerLines(end+1) = "duration: " + string(scanForSave.duration);
                end
                statusText = "INCOMPLETE";
                if isfield(scanForSave, "isComplete") && logical(scanForSave.isComplete)
                    statusText = "COMPLETE";
                end
                headerLines(end+1) = "status: " + statusText;
                if ~isempty(headerLines)
                    text_data.header = char(strjoin(headerLines, newline));
                else
                    text_data.header = '';
                end
                if isfield(scanForSave, "consts")
                    text_data.consts = scanForSave.consts;
                else
                    text_data.consts = [];
                end
                if isfield(scanForSave, "comments") && ~isempty(scanForSave.comments)
                    if iscell(scanForSave.comments)
                        text_data.body = char(scanForSave.comments{:});
                    elseif ischar(scanForSave.comments)
                        text_data.body = scanForSave.comments;
                    else
                        text_data.body = char(scanForSave.comments);
                    end
                else
                    text_data.body = '';
                end
                [pptPath, pptName, pptExt] = fileparts(pptFile);
                if strlength(pptExt) == 0
                    pptExt = ".ppt";
                end
                if strlength(pptPath) == 0
                    rootPath = experimentContext.getExperimentRootPath();
                    if strlength(rootPath) == 0
                        rootPath = string(pwd);
                    end
                    pptFile = fullfile(rootPath, pptName + pptExt);
                else
                    pptFile = fullfile(pptPath, pptName + pptExt);
                end

                text_data.imagePath = pngFile;
                text_data.forceSlideWidth = forcePptSlideWidth;
                smsaveppt(char(pptFile), text_data);
            end
        end
    catch
    end

    try
        savefig(exportFig, figstring);
    catch
    end

    if useExportCopy && ~isempty(exportFig) && ishandle(exportFig)
        delete(exportFig);
    end

    try
        if ishandle(figHandle)
            set(figHandle, "CloseRequestFcn", "closereq");
        end
    catch
    end

    function onCloseWhileSaving(~, ~)
        if closeDialogShown
            return;
        end
        closeDialogShown = true;
        msgbox("Scan finished. Saving data, please wait.", "Saving", "help");
    end
end
