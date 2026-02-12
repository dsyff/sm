function sm_Callback(what, varargin)
%#ok<*GVMIS>
%#ok<*NUSED>
% Copyright 2011 Hendrik Bluhm, Vivek Venkatachalam
% Updated 2025 for SM 1.5 Bridge System
% This file is part of Special Measure.
% 
%     Special Measure is free software: you can redistribute it and/or modify
%     it under the terms of the GNU General Public License as published by
%     the Free Software Foundation, either version 3 of the License, or
%     (at your option) any later version.
% 
%     Special Measure is distributed in the hope that it will be useful,
%     but WITHOUT ANY WARRANTY; without even the implied warranty of
%     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%     GNU General Public License for more details.
% 
%     You should have received a copy of the GNU General Public License
%     along with Special Measure.  If not, see
%     <http://www.gnu.org/licenses/>.
    if nargin < 2
        feval(what);
    else
        feval(what, varargin{1});
    end
end

function Open(h)
    global smaux bridge
    try
        smbridgeAddSharedPaths();
        if exist("bridge", "var") && ~isempty(bridge) && isobject(bridge) && isprop(bridge, "experimentRootPath")
            if strlength(string(bridge.experimentRootPath)) == 0
                bridge.experimentRootPath = pwd;
            end
        end
        smpptEnsureGlobals();
        smdatapathEnsureGlobals();
        smrunEnsureGlobals();

        smaux.sm=h;
        
        % Initialize required fields if they don't exist
        if ~isfield(smaux, 'scans')
            smaux.scans = {};
        end
        if ~isfield(smaux, 'smq')
            smaux.smq = {};
        end
        if ~isfield(smaux, 'datadir') || isempty(smaux.datadir)
            smaux.datadir = smdatapathDefaultPath();
        end
        if ~isfield(smaux, 'run')
            smaux.run = [];
        end
        if ~isfield(smaux, 'comments')
            smaux.comments = '';
        end
        
        UpdateToGUI;
        smpptAttachMainGui();
        smdatapathAttachMainGui();
        smrunAttachMainGui();
    catch ME
        % Create detailed error message
        errorMsg = sprintf('Error in Open function:\n\n%s\n\nFile: %s\nLine: %d\n\nStack trace:\n', ...
            ME.message, ME.stack(1).file, ME.stack(1).line);
        
        % Add stack trace details
        for i = 1:min(3, length(ME.stack))
            errorMsg = sprintf('%s%d. %s (line %d)\n', errorMsg, i, ME.stack(i).name, ME.stack(i).line);
        end
        
        % Show error dialog
        errordlg(errorMsg, 'SM GUI Initialization Error', 'modal');
    end
end

function Scans
end

function ScansCreate
end

function Queue
    global smaux

    UpdateToGUI;
end

function QueueCreate
end

function OpenScans
    global smaux bridge
    choice = questdlg("Load scans from folder or files?", "Open Scans", ...
        "Folder", "Files", "Cancel", "Files");
    if choice == "Folder"
        folderPath = uigetdir;
        if isequal(folderPath, 0)
            return;
        end
        listing = dir(fullfile(folderPath, "*.mat"));
        if isempty(listing)
            return;
        end
        fileList = fullfile(folderPath, {listing.name});
    elseif choice == "Files"
        [files, path] = uigetfile('*.mat', 'Select Scan File(s)', 'MultiSelect', 'on');
        if isequal(files, 0)
            return;
        end
        if iscell(files)
            fileList = fullfile(path, files);
        else
            fileList = fullfile(path, {files});
        end
    else
        return;
    end

    if ~isfield(smaux, "scans") || ~iscell(smaux.scans)
        smaux.scans = {};
    end

    for fileIdx = 1:numel(fileList)
        filePath = fileList{fileIdx};
        try
            payload = load(filePath);
        catch
            continue;
        end

        scansToAdd = {};
        if isfield(payload, "smscan") && isstruct(payload.smscan)
            scansToAdd = {payload.smscan};
        elseif isfield(payload, "scan") && isstruct(payload.scan)
            scansToAdd = {payload.scan};
        elseif isfield(payload, "scans")
            if iscell(payload.scans)
                scansToAdd = payload.scans;
            elseif isstruct(payload.scans)
                scansToAdd = num2cell(payload.scans);
            end
        end

        for scanIdx = 1:numel(scansToAdd)
            scanCandidate = scansToAdd{scanIdx};
            if ~isstruct(scanCandidate) || ~isfield(scanCandidate, "loops")
                continue;
            end
            scanCandidate = smscanSanitizeForBridge(scanCandidate);
            if isempty(scanCandidate)
                continue;
            end

            smaux.scans{end+1} = scanCandidate;
        end
    end
    UpdateToGUI;
end

function SaveScans
    global smaux bridge
    if ~isfield(smaux, "scans") || isempty(smaux.scans)
        return;
    end
    rootPath = string(pwd);
    if exist("bridge", "var") && ~isempty(bridge) && isobject(bridge) && isprop(bridge, "experimentRootPath")
        if strlength(string(bridge.experimentRootPath)) == 0
            bridge.experimentRootPath = pwd;
        end
        rootPath = string(bridge.experimentRootPath);
    end
    timestamp = char(datetime("now", "Format", "yyyyMMdd_HHmmss"));
    targetFolder = fullfile(rootPath, "scans_" + string(timestamp));
    if ~exist(targetFolder, "dir")
        mkdir(targetFolder);
    end

    for scanIdx = 1:numel(smaux.scans)
        scanCandidate = smaux.scans{scanIdx};
        if ~isstruct(scanCandidate)
            continue;
        end
        baseName = "scan";
        if isfield(scanCandidate, "name") && ~isempty(scanCandidate.name)
            baseName = string(scanCandidate.name);
        end
        baseName = regexprep(baseName, '[\\/:*?"<>|.]', "_");
        filename = baseName;
        suffix = 0;
        while exist(fullfile(targetFolder, filename + ".mat"), "file")
            suffix = suffix + 1;
            filename = baseName + " (" + suffix + ")";
        end
        smscan = scanCandidate;
        save(fullfile(targetFolder, filename + ".mat"), "smscan");
    end
end



function SMusers
    global smaux
    user_index=get(smaux.sm.smusers_lbh,'Value');
    if isempty(user_index)
        return;
    end
    for user_ind = user_index
        smaux.users(user_ind).notifyon = ~smaux.users(user_ind).notifyon;
    end
    UpdateToGUI;
end

function SMusersCreate
end

function Enqueue
    global smaux smscan;
    scan_index=get(smaux.sm.scans_lbh,'Value');
    if isempty(scan_index)
        return;
    end
    scan = smaux.scans{scan_index};
    queue_index=get(smaux.sm.queue_lbh,'Value');
    if ~isfield(smaux,'smq')
        smaux.smq{1}=scan;
    else
        smaux.smq=[smaux.smq(1:queue_index) scan smaux.smq(queue_index+1:end)];
    end
    UpdateToGUI;
end

function EditScan
    global smaux smscan;
    try
        queue_index=get(smaux.sm.queue_lbh,'Value');
        if isempty(queue_index) || queue_index == 0
            return;
        end
        if queue_index > length(smaux.smq)
            queue_index = length(smaux.smq);
        end
        if ~isfield(smaux.smq{queue_index},'loops') && isfield(smaux.smq{queue_index},'eval')
            set(smaux.sm.qtxt_eth,'String',smaux.smq{queue_index}.eval);
            smaux.smq(queue_index)=[];
        else
            smscan = smaux.smq{queue_index};
            smgui_small;
        end
        UpdateToGUI;
    catch ME
        % Create detailed error message
        errorMsg = sprintf('Error in EditScan:\n\n%s\n\nFile: %s\nLine: %d\n\nStack trace:\n', ...
            ME.message, ME.stack(1).file, ME.stack(1).line);
        
        % Add stack trace details
        for i = 1:min(3, length(ME.stack))
            errorMsg = sprintf('%s%d. %s (line %d)\n', errorMsg, i, ME.stack(i).name, ME.stack(i).line);
        end
        
        % Show error dialog
        errordlg(errorMsg, 'EditScan Error', 'modal');
    end
end

function EditScan2
    global smaux smscan;
    try
        scan_index=get(smaux.sm.scans_lbh,'Value');
        if isempty(scan_index)
            return;
        end
        smscan = smaux.scans{scan_index};
        smgui_small;
    catch ME
        % Create detailed error message
        errorMsg = sprintf('Error in EditScan2:\n\n%s\n\nFile: %s\nLine: %d\n\nStack trace:\n', ...
            ME.message, ME.stack(1).file, ME.stack(1).line);
        
        % Add stack trace details
        for i = 1:min(3, length(ME.stack))
            errorMsg = sprintf('%s%d. %s (line %d)\n', errorMsg, i, ME.stack(i).name, ME.stack(i).line);
        end
        
        % Show error dialog
        errordlg(errorMsg, 'EditScan2 Error', 'modal');
    end
end

function RemoveScan
    global smaux

    UpdateToGUI;
end

function Qtxt
end

function TXTenqueue
    global smaux
    clear scan;
    scan.eval = get(smaux.sm.qtxt_eth,'String');
    set(smaux.sm.qtxt_eth,'String','');
    scan.name = ['EVAL(' scan.eval(1,:) '...)'];
    queue_index=get(smaux.sm.queue_lbh,'Value');
    if ~isfield(smaux,'smq')
        smaux.smq{1}=scan;
    else
        smaux.smq=[smaux.smq(1:queue_index) scan smaux.smq(queue_index+1:end)];
    end
    UpdateToGUI;
end

function PPTauto
    global smaux
    smpptEnsureGlobals();
    enabled = false;
    if isstruct(smaux) && isfield(smaux, 'sm') && isstruct(smaux.sm) ...
            && isfield(smaux.sm, 'pptauto_cbh') && ishandle(smaux.sm.pptauto_cbh)
        enabled = logical(get(smaux.sm.pptauto_cbh, 'Value'));
    end
    [~, currentFile] = smpptGetState();
    smpptUpdateGlobalState('main', enabled, currentFile);
end

function PPTFile
    global smaux bridge
    [pptFile, ~] = uiputfile('*.ppt', 'Append to Presentation');
    if isequal(pptFile, 0)
        return;
    end
    rootPath = string(pwd);
    if exist("bridge", "var") && ~isempty(bridge) && isobject(bridge) && isprop(bridge, "experimentRootPath")
        if strlength(string(bridge.experimentRootPath)) == 0
            bridge.experimentRootPath = pwd;
        end
        rootPath = string(bridge.experimentRootPath);
    end
    [~, pptName, pptExt] = fileparts(pptFile);
    if strlength(string(pptExt)) == 0
        pptExt = ".ppt";
    end
    selectedFile = fullfile(rootPath, string(pptName) + string(pptExt));
    enabled = false;
    if isstruct(smaux) && isfield(smaux, 'sm') && isstruct(smaux.sm) ...
            && isfield(smaux.sm, 'pptauto_cbh') && ishandle(smaux.sm.pptauto_cbh)
        enabled = logical(get(smaux.sm.pptauto_cbh, 'Value'));
    end
    smpptUpdateGlobalState('main', enabled, selectedFile);
end    

function PPTFile2
    global smaux
    [pptFile,pptPath] = uiputfile('*.ppt','Append to Presentation');
    if pptFile
        smaux.pptsavefile2=fullfile(pptPath,pptFile);   
        set(smaux.sm.pptfile2_sth,'String',pptFile);
        set(smaux.sm.pptfile2_sth,'TooltipString',smaux.pptsavefile);
    end    
end 

function PPTSaveFig
    global smaux
    if ~ishandle(str2double(get(smaux.sm.pptsave_eth,'String')))
        errordlg('Invalid Figure Handle');
        set(smaux.sm.pptsave_eth,'String',1000);
    end
end

function PPTSaveNow
    global smaux
    % PowerPoint save functionality is handled by measurementEngine
end 

function PPTPriority
    global smaux

    UpdateToGUI;
end

function Comments
    global smaux
    smaux.comments=get(smaux.sm.comments_eth,'String');
end

function SavePath
    global smaux bridge
    x = uigetdir;
    if x
        rootPath = string(pwd);
        if exist("bridge", "var") && ~isempty(bridge) && isobject(bridge) && isprop(bridge, "experimentRootPath")
            if strlength(string(bridge.experimentRootPath)) == 0
                bridge.experimentRootPath = pwd;
            end
            rootPath = string(bridge.experimentRootPath);
        end
        pickedPath = string(x);
        targetPath = pickedPath;
        if strlength(rootPath) > 0
            if startsWith(pickedPath, rootPath, "IgnoreCase", true)
                relPath = extractAfter(pickedPath, strlength(rootPath));
                if startsWith(relPath, filesep)
                    relPath = extractAfter(relPath, 1);
                end
                if strlength(relPath) == 0
                    relPath = "data";
                end
            else
                [~, relPath] = fileparts(char(pickedPath));
                relPath = string(relPath);
                if strlength(relPath) == 0
                    relPath = "data";
                end
            end
            targetPath = fullfile(rootPath, relPath);
        end
        smaux.datadir = targetPath;
        smdatapathUpdateGlobalState("main", smaux.datadir);
    end
    UpdateToGUI;
end

function RunNum
    global smaux
    s=get(smaux.sm.run_eth,'String');
    if isempty(s)
        set(smaux.sm.runincrement_cbh,'Value',0);
        smrunUpdateGlobalState('main', []);
    else
        val = str2double(s);
        if ~isnan(val) && isfinite(val) && val>=0 && val<=999
            smrunUpdateGlobalState('main', val);
        else
            errordlg('Please enter an integer in [000 999]','Bad Run Number');
            smrunUpdateGlobalState('main', []);
        end
    end
    smrunApplyStateToGui('main');
end

function RunCreate
end

function RunIncrement
end

function Run
    global smaux engine
    try
        while ~isempty(smaux.smq)
            %grab the next scan in the queue
            scan = smaux.smq{1};
            smaux.smq(1)=[];
            UpdateToGUI;
            
            if ~isfield(scan,'loops') && isfield(scan,'eval') %to evaluate commands
                evalLines = scan.eval;
                for i = 1:size(evalLines, 1)
                    evalin("base", evalLines(i, :));
                end
            else
                %filename for this run - final safety net: sanitize for Windows invalid chars
                scan_file_name = regexprep(scan.name, '[\\/:*?"<>|.]', '_');
                if ~isfield(smaux,'datadir') || isempty(smaux.datadir)
                    smaux.datadir = smdatapathDefaultPath();
                end
                if ~exist(smaux.datadir, 'dir')
                    mkdir(smaux.datadir);
                end
                smdatapathUpdateGlobalState('main', smaux.datadir);
                
                scan = ensureScanPpt(scan);
                scan.name = char(string(scan_file_name));
                if ~exist("engine", "var") || isempty(engine) || ~isa(engine, "measurementEngine")
                    error("sm:MissingEngine", "measurementEngine not found. Please run smready(...) first.");
                end
                engine.run(scan, "", "turbo");
                UpdateToGUI;
                drawnow;
                pause(3);
            end
        end
    catch ME
        % Create detailed error message
        errorMsg = sprintf('Error in Run function:\n\n%s\n\nFile: %s\nLine: %d\n\nStack trace:\n', ...
            ME.message, ME.stack(1).file, ME.stack(1).line);
        
        % Add stack trace details
        for i = 1:min(3, length(ME.stack))
            errorMsg = sprintf('%s%d. %s (line %d)\n', errorMsg, i, ME.stack(i).name, ME.stack(i).line);
        end
        
        % Show error dialog
        errordlg(errorMsg, 'Run Function Error', 'modal');
    end
end

function Pause
    pause
end

function QueueKey(eventdata)
    global smaux
    if strcmp(eventdata.Key,'delete')
        queue_index=get(smaux.sm.queue_lbh,'Value');
        if queue_index>0
            smaux.smq(queue_index) = [];
            if queue_index > length(smaux.smq) && ~isempty(smaux.smq)
                queue_index = length(smaux.smq);
                set(smaux.sm.queue_lbh,'Value',queue_index);
            end
            UpdateToGUI;
        end
    end
end

function ScansKey(eventdata)
    global smaux
    if strcmp(eventdata.Key,'delete')
        scan_index=get(smaux.sm.scans_lbh,'Value');
        if scan_index>0
            smaux.scans(scan_index) = [];
            if scan_index > length(smaux.scans) && ~isempty(smaux.scans)
                scan_index = length(smaux.scans);
                set(smaux.sm.scans_lbh,'Value',scan_index);
            end
            UpdateToGUI;
        end
    end
end

function Console
end

function Eval
    global smaux
    cmdLines = get(smaux.sm.console_eth, 'String');
    set(smaux.sm.console_eth, 'String', '');
    for i = 1:size(cmdLines, 1)
        evalin("base", cmdLines(i, :));
    end
end

function scan = UpdateConstants(scan)
    global smaux smscan engine;
    
    try
        if nargin==0
            scan = smscan;
        end

        if ~exist("engine", "var") || isempty(engine) || ~isa(engine, "measurementEngine")
            error("sm:MissingEngine", "measurementEngine not found. Please run smready(...) first.");
        end

        if ~isfield(scan, "consts") || isempty(scan.consts)
            return;
        end

        consts = scan.consts;
        if ~isfield(consts, "set")
            [consts.set] = deal(1);
        end

        setMask = [consts.set] == 1;
        if any(setMask)
            setchans = string({consts(setMask).setchan});
            setvals = double([consts(setMask).val]).';
            engine.rackSet(setchans(:), setvals);
        end

        getMask = ~setMask;
        if ~any(getMask)
            return;
        end

        getchans = string({consts(getMask).setchan});
        newvals = engine.rackGet(getchans(:));
        getIdx = find(getMask);
        for k = 1:numel(getIdx)
            scan.consts(getIdx(k)).val = newvals(k);
        end
    catch ME
        % Create detailed error message
        errorMsg = sprintf('Error in UpdateConstants:\n\n%s\n\nFile: %s\nLine: %d\n\nStack trace:\n', ...
            ME.message, ME.stack(1).file, ME.stack(1).line);
        
        % Add stack trace details
        for i = 1:min(3, length(ME.stack))
            errorMsg = sprintf('%s%d. %s (line %d)\n', errorMsg, i, ME.stack(i).name, ME.stack(i).line);
        end
        
        % Show error dialog
        errordlg(errorMsg, 'UpdateConstants Error', 'modal');
        % Return the scan unchanged if there's an error
        if nargin==0
            scan = smscan;
        end
    end
end

function UpdateToGUI
    global smaux bridge
    try
        %populates available scans
        scannames = {};
        scan_index=get(smaux.sm.scans_lbh,'Value');
        if isempty(scan_index)
            scan_index = 0;
        end
        if isfield(smaux,'scans') && iscell(smaux.scans)
            scannames = cell(1, length(smaux.scans));
            for i=1:length(smaux.scans)
                if ~isfield(smaux.scans{i},'name')
                    smaux.scans{i}.name=['Scan ' num2str(i)];
                end
                scannames{i}=smaux.scans{i}.name;
            end
        else
            smaux.scans = {};
        end
        set(smaux.sm.scans_lbh,'String',scannames);
        if scan_index>length(smaux.scans) || (scan_index==0 && ~isempty(smaux.scans))
            set(smaux.sm.scans_lbh,'Value',length(smaux.scans));
        end
        
        %populates queue list box
        qnames = {};
        
        queue_index=get(smaux.sm.queue_lbh,'Value');
        if isempty(queue_index) && ~isempty(get(smaux.sm.queue_lbh,'String'))
            queue_index = 1;
            set(smaux.sm.queue_lbh,'Value',queue_index);
        end
        queue_index=get(smaux.sm.queue_lbh,'Value');
        if isempty(queue_index)
            queue_index = 0;
        end
        
        if isfield(smaux,'smq') && iscell(smaux.smq)
            qnames = cell(1, length(smaux.smq));
            for i=1:length(smaux.smq)
                if isfield(smaux.smq{i},'name')
                    qnames{i}=smaux.smq{i}.name;
                else
                    qnames{i}='Unnamed Scan';
                end
            end
        else
            smaux.smq={};
        end
        set(smaux.sm.queue_lbh,'String',qnames);
        if queue_index>length(smaux.smq) || (queue_index==0 && ~isempty(smaux.smq))
            set(smaux.sm.queue_lbh,'Value',length(smaux.smq));
        end
        
        %populate data path sth
        rootPath = string(pwd);
        if exist("bridge", "var") && ~isempty(bridge) && isobject(bridge) && isprop(bridge, "experimentRootPath")
            if strlength(string(bridge.experimentRootPath)) == 0
                bridge.experimentRootPath = pwd;
            end
            rootPath = string(bridge.experimentRootPath);
        end
        if isfield(smaux, 'datadir') && ~isempty(smaux.datadir)
            candidatePath = string(smaux.datadir);
            if ~startsWith(candidatePath, rootPath, "IgnoreCase", true)
                [~, relPath] = fileparts(char(candidatePath));
                relPath = string(relPath);
                if strlength(relPath) == 0
                    relPath = "data";
                end
                smaux.datadir = fullfile(rootPath, relPath);
            end
        else
            smaux.datadir = smdatapathDefaultPath();
        end
        if ~exist(smaux.datadir, 'dir')
            mkdir(smaux.datadir);
        end
        currentPath = smdatapathGetState();
        if ~strcmp(char(currentPath), char(smaux.datadir))
            smdatapathUpdateGlobalState("main", smaux.datadir);
        else
            smdatapathApplyStateToGui("main");
        end
        
        %populate run number eth
        smrunApplyStateToGui('main');
        
        %populate powerpoint main file sth
        [pptEnabledMain, pptFileMain] = smpptGetState();
        if isfield(smaux.sm, 'pptauto_cbh') && ishandle(smaux.sm.pptauto_cbh)
            set(smaux.sm.pptauto_cbh, 'Value', double(pptEnabledMain));
        end
        if isfield(smaux.sm, 'pptfile_sth') && ishandle(smaux.sm.pptfile_sth)
            if isempty(pptFileMain)
                displayName = '';
            else
                [~, name, ext] = fileparts(pptFileMain);
                displayName = [name ext];
            end
            set(smaux.sm.pptfile_sth, 'String', displayName);
            set(smaux.sm.pptfile_sth, 'TooltipString', pptFileMain);
        end
        
        %populate powerpoint priority file sth
        if isfield(smaux,'pptsavefile2') && exist(smaux.pptsavefile2,'file')
            [~, name, ext] = fileparts(smaux.pptsavefile2);
            set(smaux.sm.pptfile2_sth,'String',[name ext]);
            set(smaux.sm.pptfile2_sth,'TooltipString',smaux.pptsavefile2);
        end
        
        %populate comment text
        if ~isfield(smaux,'comments')
            smaux.comments='';
        end
        set(smaux.sm.comments_eth,'String',smaux.comments);
        
        %populate smusers listbox
        if isfield(smaux,'users')
            set(smaux.sm.smusers_lbh,'String',{smaux.users.name});
            set(smaux.sm.smusers_lbh,'Value',find(cell2mat({smaux.users.notifyon})));
        end
        
        % Force pending GUI updates to render before returning.
        drawnow;
    catch ME
        % Create detailed error message
        errorMsg = sprintf('Error in UpdateToGUI:\n\n%s\n\nFile: %s\nLine: %d\n\nStack trace:\n', ...
            ME.message, ME.stack(1).file, ME.stack(1).line);
        
        % Add stack trace details
        for i = 1:min(3, length(ME.stack))
            errorMsg = sprintf('%s%d. %s (line %d)\n', errorMsg, i, ME.stack(i).name, ME.stack(i).line);
        end
        
        % Show error dialog
        errordlg(errorMsg, 'UpdateToGUI Error', 'modal');
    end
end


function scan = ensureScanPpt(scan)
    smpptEnsureGlobals();
    if ~isstruct(scan)
        return;
    end
    if isfield(scan, 'ppt')
        scan = rmfield(scan, 'ppt');
    end
end


function smpptAttachMainGui()
    global smaux bridge
    smpptEnsureGlobals();
    if ~isstruct(smaux) || ~isfield(smaux, 'sm') || ~isstruct(smaux.sm)
        return;
    end
    handles.figure = [];
    if isfield(smaux.sm, 'figure1')
        handles.figure = smaux.sm.figure1;
    end
    handles.checkbox = [];
    if isfield(smaux.sm, 'pptauto_cbh')
        handles.checkbox = smaux.sm.pptauto_cbh;
    end
    handles.fileLabel = [];
    if isfield(smaux.sm, 'pptfile_sth')
        handles.fileLabel = smaux.sm.pptfile_sth;
    end
    [currentEnabled, currentFile] = smpptGetState();
    targetEnabled = currentEnabled;
    if ishandle(handles.checkbox)
        targetEnabled = logical(get(handles.checkbox, 'Value'));
    end
    targetFile = currentFile;
    rootPath = string(pwd);
    if exist("bridge", "var") && ~isempty(bridge) && isobject(bridge) && isprop(bridge, "experimentRootPath")
        if strlength(string(bridge.experimentRootPath)) == 0
            bridge.experimentRootPath = pwd;
        end
        rootPath = string(bridge.experimentRootPath);
    end
    if isempty(targetFile)
        if isfield(smaux, 'pptsavefile') && ~isempty(smaux.pptsavefile)
            targetFile = smaux.pptsavefile;
        else
            % Set default short name
            targetFile = "log.ppt";
        end
    end
    if strlength(rootPath) > 0
        [~, pptName, pptExt] = fileparts(targetFile);
        if strlength(string(pptExt)) == 0
            pptExt = ".ppt";
        end
        targetFile = fullfile(rootPath, string(pptName) + string(pptExt));
    end
    if targetEnabled ~= currentEnabled || ~strcmp(char(targetFile), char(currentFile))
        smpptUpdateGlobalState('main', targetEnabled, targetFile);
    end
end


function smdatapathAttachMainGui()
    global smaux
    smdatapathEnsureGlobals();
    if ~isstruct(smaux) || ~isfield(smaux, 'sm') || ~isstruct(smaux.sm)
        return;
    end
    handles = struct();
    if isfield(smaux.sm, 'datapath_sth')
        handles.label = smaux.sm.datapath_sth;
        handles.tooltipHandle = smaux.sm.datapath_sth;
        handles.displayLimit = 40;
    end
    smdatapathRegisterGui('main', handles);
end


function smrunAttachMainGui()
    global smaux
    smrunEnsureGlobals();
    if ~isstruct(smaux) || ~isfield(smaux, 'sm') || ~isstruct(smaux.sm)
        return;
    end
    handles = struct();
    if isfield(smaux.sm, 'run_eth')
        handles.edit = smaux.sm.run_eth;
        handles.tooltipHandle = smaux.sm.run_eth;
    end
    smrunRegisterGui('main', handles);
end

