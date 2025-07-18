function sm_new_Callback(what,arg)
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
    switch nargin
        case 1
            eval(what);
        case 2
            eval([what '(arg);']);
    end
end

function Open(h)
    global smaux
    try
        smaux.sm=h;
        
        % Initialize required fields if they don't exist
        if ~isfield(smaux, 'scans')
            smaux.scans = {};
        end
        if ~isfield(smaux, 'smq')
            smaux.smq = {};
        end
        if ~isfield(smaux, 'datadir')
            smaux.datadir = pwd;
        end
        if ~isfield(smaux, 'run')
            smaux.run = uint16(1);
        end
        if ~isfield(smaux, 'comments')
            smaux.comments = '';
        end
        
        UpdateToGUI;
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
    global smaux
    [file,path] = uigetfile('*.mat','Select Rack File');
    if file
        load(fullfile(path,file));
        if exist('scans','var')
            smaux.scans=scans;
        end
    end
    UpdateToGUI;
end

function SaveScans
    global smaux
    [file,path] = uiputfile('*.mat','Save Scan File');
    if file
        scans = smaux.scans;
        save(fullfile(path,file),'scans');
    end
end

function OpenRack
    global smaux
    [file,path] = uigetfile('*.mat','Select Rack File');
    if file
        load(fullfile(path,file));
    end
    UpdateToGUI;
end

function SaveRack
    global smaux
    [file,path] = uiputfile('*.mat','Save Rack File');
    if file
        save(fullfile(path,file),'smdata');
    end
end

function EditRack
    smdataman;
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
            smgui_small_new;  % Updated to use new version
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
        smgui_small_new;  % Updated to use new version
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
end

function PPTFile
    global smaux
    [pptFile,pptPath] = uiputfile('*.ppt','Append to Presentation');
    if pptFile
        smaux.pptsavefile=fullfile(pptPath,pptFile);   
        set(smaux.sm.pptfile_sth,'String',pptFile);
        set(smaux.sm.pptfile_sth,'TooltipString',smaux.pptsavefile);
    end    
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
    if ~ishandle(str2num(get(smaux.sm.pptsave_eth,'String')))
        errordlg('Invalid Figure Handle');
        set(smaux.sm.pptsave_eth,'String',1000);
    end
end

function PPTSaveNow
    global smaux
    % PowerPoint save functionality moved to smrun_new
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
    global smaux
    x=uigetdir;
    if x
        smaux.datadir = x;
    end
    UpdateToGUI;
end

function RunNum
    global smaux
    s=get(smaux.sm.run_eth,'String');
    if isempty(s)
        set(smaux.sm.runincrement_cbh,'Value',0);
        smaux.run=[];  
    else
        val = str2double(s)
        if ~isnan(val) && isinteger(uint16(val)) && uint16(val)>=0 && uint16(val)<=999
            smaux.run=uint16(val);
            set(smaux.sm.run_eth,'String',smaux.run);
        else
            errordlg('Please enter an integer in [000 999]','Bad Run Number');
            set(smaux.sm.run_eth,'String','');
        end
    end
end

function RunCreate
end

function RunIncrement
end

function Run
    global smaux
    try
        while ~isempty(smaux.smq);
            %grab the next scan in the queue
            scan = smaux.smq{1};
            smaux.smq(1)=[];
            UpdateToGUI;
            
            if ~isfield(scan,'loops') && isfield(scan,'eval') %to evaluate commands
                string=scan.eval;
                for i=1:size(string,1)
                    evalin('base',string(i,:));
                end
            else
                %filename for this run
                runstring=sprintf('%03u',smaux.run);
                scan_file_name = replace(scan.name, ".", "_"); %Thomas 20240611 sanitize scan name for saving
                datasaveFile = fullfile(smaux.datadir,[runstring  '_' scan_file_name '.mat']);
                while exist(datasaveFile,'file')
                    smaux.run=smaux.run+1;
                    runstring=sprintf('%03u',smaux.run);
                    datasaveFile = fullfile(smaux.datadir,[runstring  '_' scan_file_name '.mat']);
                end
                
                scan = UpdateConstants(scan);
                smrun_new(scan,datasaveFile);  % Updated to use new version
                
                %save to powerpoint
                if get(smaux.sm.pptauto_cbh,'Value')
                    try
                        slide.title = [runstring  '_' scan_file_name '.mat'];
                        % Safely handle comments
                        if ~isfield(scan,'comments')
                            scan.comments = '';
                        end
                        if ischar(smaux.comments) && ischar(scan.comments)
                            slide.body = strvcat(smaux.comments,scan.comments);
                        elseif ischar(smaux.comments)
                            slide.body = smaux.comments;
                        elseif ischar(scan.comments)
                            slide.body = scan.comments;
                        else
                            slide.body = '';
                        end
                        % PowerPoint save functionality moved to smrun_new
                    catch ME_ppt
                        % PowerPoint save functionality moved to smrun_new
                    end
                end
                smaux.run=smaux.run+1; %increment run number;
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
    string=get(smaux.sm.console_eth,'String');
    set(smaux.sm.console_eth,'String','');
    for i=1:size(string,1)
        evalin('base',string(i,:));
    end
end

function scan = UpdateConstants(scan)
    global smaux smscan;
    
    try
        if nargin==0
            scan = smscan;
        end
        allchans = {};
        if isfield(scan.consts,'setchan')
            allchans = {scan.consts.setchan};
        end
        setchans = {};
        setvals = [];
        for i=1:length(scan.consts)
            if scan.consts(i).set
                setchans{end+1}=scan.consts(i).setchan;
                setvals(end+1)=scan.consts(i).val;
            end
        end
        smset_new(setchans, setvals);  % Updated to use new version
        newvals = cell2mat(smget_new(allchans));  % Updated to use new version
        for i=1:length(scan.consts)
            scan.consts(i).val=newvals(i);
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
    global smaux
    try
        %populates available scans
        scannames = {};
        scan_index=get(smaux.sm.scans_lbh,'Value');
        if isempty(scan_index)
            scan_index = 0;
        end
        if isfield(smaux,'scans') && iscell(smaux.scans)
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
        if isfield(smaux,'datadir') && exist(smaux.datadir,'dir')
            seplocations=findstr(filesep,smaux.datadir);
            if length(seplocations)>1
                displaystring=smaux.datadir(seplocations(end-1)+1:end);
            else
                displaystring=smaux.datadir;
            end
            if length(displaystring)>40
                displaystring=displaystring(end-39:end);
            end
            set(smaux.sm.datapath_sth,'String',displaystring);
            set(smaux.sm.datapath_sth,'TooltipString',smaux.datadir);
        end
        
        %populate run number eth
        if isfield(smaux,'run') && isinteger(smaux.run)
            val = smaux.run;
            if ~isnan(val) && isinteger(uint16(val)) && uint16(val)>=0 && uint16(val)<=999
                smaux.run=uint16(val);
                set(smaux.sm.run_eth,'String',smaux.run);
            else
                errordlg('Please enter an integer in [000 999]','Bad Run Number');
                set(smaux.sm.run_eth,'String','');
            end
        end
        
        %populate powerpoint main file sth
        if isfield(smaux,'pptsavefile') && exist(smaux.pptsavefile,'file')
            [pathstr, name, ext] = fileparts(smaux.pptsavefile);
            set(smaux.sm.pptfile_sth,'String',[name ext]);
            set(smaux.sm.pptfile_sth,'TooltipString',smaux.pptsavefile);
        end
        
        %populate powerpoint priority file sth
        if isfield(smaux,'pptsavefile2') && exist(smaux.pptsavefile2,'file')
            [pathstr, name, ext] = fileparts(smaux.pptsavefile2);
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
