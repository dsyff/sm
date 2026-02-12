function varargout = smgui_small(varargin)
%#ok<*GVMIS>
%#ok<*INUSD>
%#ok<*NUSED>
% Runs special measure's GUI
% to fix: -- deselect plots after changing setchannels
%         -- selecting files/directories/run numbers
%         -- add notifications + smaux compatibility

% Copyright 2011 Hendrik Bluhm, Vivek Venkatachalam
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

%thomas 2023.12
 global smdata smscan smaux rack bridge;
varargout = cell(1, nargout);
 
 smbridgeAddSharedPaths();
 smpptEnsureGlobals();
 smdatapathEnsureGlobals();
 smrunEnsureGlobals();
 
% Initialize global variables if they don't exist
if ~exist('smscan', 'var') || isempty(smscan)
    smscan.loops(1).npoints = 101;
    smscan.loops(1).rng = [0 1];
    smscan.loops(1).getchan = {};
    smscan.loops(1).setchan = {};
    smscan.loops(1).setchanranges = {};
    smscan.loops(1).ramptime = [];
    smscan.loops(1).numchans = 0;
    smscan.loops(1).waittime = 0;
    smscan.data = [];
    smscan.consts = struct('setchan', {}, 'val', {}, 'set', {});
    % Add missing fields that scaninit expects
    smscan.saveloop = 2;  % Default to loop 2
    smscan.disp = [];     % Empty display configuration
end

if ~exist('smaux', 'var') || isempty(smaux)
    smaux = struct();
end

% Check if smdata exists - if not, warn user to run setup
if ~exist('smdata', 'var') || isempty(smdata)
    error('smdata not initialized. Please run: setupSmguiWithNewInstruments() first');
end

% Initialize bridge if it doesn't exist but rack does
if ~exist('bridge', 'var') || isempty(bridge)
    if exist('rack', 'var') && ~isempty(rack) && isa(rack, 'instrumentRack')
        bridge = smguiBridge(rack);
        bridge.initializeSmdata();  % This will properly set up smdata with vector channel support
    end
end

% Ensure experimentRootPath is set early for path defaults.
if exist("bridge", "var") && ~isempty(bridge) && isobject(bridge) && isprop(bridge, "experimentRootPath")
    if strlength(string(bridge.experimentRootPath)) == 0
        bridge.experimentRootPath = pwd;
    end
    rootPath = string(bridge.experimentRootPath);
    if strlength(rootPath) > 0
        currentPath = smdatapathGetState();
        if ~startsWith(string(currentPath), rootPath, "IgnoreCase", true)
            smaux.datadir = fullfile(rootPath, "data");
            smdatapathUpdateGlobalState("small", smaux.datadir);
        end
    end
end


 
if nargin > 0
    if nargout > 0
        [varargout{1:nargout}] = feval(varargin{:});
    else
        feval(varargin{:});
    end
    return;
end

    if isfield(smaux,'smgui') && ishandle(smaux.smgui.figure1)
        Update
        figure(smaux.smgui.figure1)
        movegui(smaux.smgui.figure1,'center')
        return
    end
    figHeight = 900;
    %  Create and then hide the GUI as it is being constructed.
   smaux.smgui.figure1 = figure('Visible','on',...
       'Name','Special Measure v0.9',...
       'MenuBar','none', ...
       'NumberTitle','off',...
       'IntegerHandle','off',...
       'Position',[0,0,900,figHeight],...
       'Toolbar','none',...
       'Resize','off');
   movegui(smaux.smgui.figure1,'center')

   %put everything in this panel for aesthetic purposes
   smaux.smgui.nullpanel=uipanel('Parent',smaux.smgui.figure1,...
        'Units','pixels','Position',[0,0,905,figHeight]);
    
    %Menu Configuration
   smaux.smgui.FileMenu = uimenu('Parent',smaux.smgui.figure1,...
        'HandleVisibility','callback',...
        'Label','File');
    
        smaux.smgui.OpenScan = uimenu('Parent',smaux.smgui.FileMenu,...
            'Label','Open Scan',...
            'HandleVisibility','Callback',...
            'Accelerator','o',...
            'Callback',@LoadScan);
        smaux.smgui.SaveScan = uimenu('Parent',smaux.smgui.FileMenu,...
            'Label','Save Scan',...
            'HandleVisibility','Callback',...
            'Accelerator','s',...
            'Callback',@SaveScan);
        smaux.smgui.EditRack = uimenu('Parent',smaux.smgui.FileMenu,...
            'Separator','on',...
            'Label','Edit Rack',...
            'HandleVisibility','Callback',...
            'Callback',@EditRack);

    smaux.smgui.scan_constants_ph = [];
        smaux.smgui.update_consts_pbh = []; %pb to update all the scan constants (run smset)
        smaux.smgui.consts_pmh = []; %1d array of popups for scan constants (set)
        smaux.smgui.consts_eth = []; %1d array of edits for scan constants (set)
        smaux.smgui.setconsts_cbh=[];
    smaux.smgui.loop_panels_ph = []; % handles to panels for each loop
    smaux.smgui.loopvars_sth = []; % handles to static text for each loop (2D)
    smaux.smgui.loopvars_eth = []; % handles to edit text for each loop (2D)
    smaux.smgui.loopvars_getchans_pmh = []; %getchannel popups for each loop (2D)
    smaux.smgui.loopcvars_sth = []; % loop channel variables for each loop setchannel (3D)
    smaux.smgui.loopcvars_eth = []; % edit text for setchannels (3D)
    smaux.smgui.loopcvars_delchan_pbh=[]; %delete loop setchannel pushbuttons
    

    
    
    panYscan = figHeight-70;
    smaux.smgui.scantitle_panel = uipanel('Parent',smaux.smgui.nullpanel,'Title','Scan Name',...
        'Units','pixels',...
        'Position',[3 panYscan 174 40]);
        smaux.smgui.scantitle_eth = uicontrol('Parent',smaux.smgui.scantitle_panel,'Style','edit',...
            'String','',...
            'HorizontalAlignment','left',...
            'FontSize',8,...
            'Position',[3 4 166 20],...
            'Callback',@ScanTitle);

    panYppt = panYscan - 65;
    smaux.smgui.pptpanel = uipanel('Parent',smaux.smgui.nullpanel,'Title','PowerPoint Log',...
        'Units','pixels',...
        'Position',[3 panYppt 174 60]);
        smaux.smgui.saveppt_pbh = uicontrol('Parent',smaux.smgui.pptpanel,'Style','pushbutton',...
            'String','File',...
            'Position',[4 27 60 20],...
            'FontSize',8,...
            'Callback',@SavePPT); 
        smaux.smgui.pptfile_sth = uicontrol('Parent',smaux.smgui.pptpanel,'Style','text',...
            'String','',...
            'HorizontalAlignment','center',...
            'FontSize',7,...
            'Position',[2 2 167 23]);
        smaux.smgui.appendppt_cbh = uicontrol('Parent',smaux.smgui.pptpanel,'Style','checkbox',...
            'String','Log',...
            'Position',[100 26 60 20],...
            'HorizontalAlignment','left',...
            'FontSize',8,...
            'Value',1,...
            'Callback',@AppendPptToggle);
        
    smaux.smgui.datapanel = uipanel('Parent',smaux.smgui.nullpanel,'Title','Data File',...
        'Units','pixels',...
        'Position',[180 figHeight-120 474 88]); %[3 700 174 88]
        smaux.smgui.savedata_pbh = uicontrol('Parent',smaux.smgui.datapanel,'Style','pushbutton',...
            'String','Path',...
            'Position',[4 53 60 20],...
            'Callback',@SavePath);
        smaux.smgui.datapath_sth = uicontrol('Parent',smaux.smgui.datapanel,'Style','text',...
            'String','',...
            'HorizontalAlignment','left',...
            'FontSize',8,...
            'Max',50,...
            'Position',[70 50 390 20]);
        smaux.smgui.filename_pbh = uicontrol('Parent',smaux.smgui.datapanel,'Style','pushbutton',...
            'String','File',...
            'HorizontalAlignment','right',...
            'FontSize',8,...
            'ToolTipString','Full file name = path\filename_run.mat',...
            'Position',[4 28 50 20],...
            'Callback',@FileName);
        smaux.smgui.filename_eth = uicontrol('Parent',smaux.smgui.datapanel,'Style','edit',...
            'String','',...
            'HorizontalAlignment','left',...
            'FontSize',8,...
            'Position',[65 30 250 15]);
        smaux.smgui.runnumber_sth = uicontrol('Parent',smaux.smgui.datapanel,'Style','text',...
            'String','Run:',...
            'HorizontalAlignment','right',...
            'FontSize',8,...
            'Position',[4 5 30 15]);
        smaux.smgui.runnumber_eth = uicontrol('Parent',smaux.smgui.datapanel,'Style','edit',...
            'String','',...
            'HorizontalAlignment','left',...
            'FontSize',8,...
            'Position',[40 5 25 15],...
            'Callback',@RunNumber);
        if ~isfield(smaux, "run")
            smaux.run = [];
        end
        smaux.smgui.autoincrement_cbh = uicontrol('Parent',smaux.smgui.datapanel,'Style','checkbox',...
            'String','AutoIncrement',...
            'HorizontalAlignment','left',...
            'FontSize',7,...
            'ToolTipString','Selecting this will automatically increase run after hitting measure',...
            'Position',[90 5 80 15],...
            'Value',1);   
        
            
    
    panYloops = panYppt-35;
    smaux.smgui.numloops_sth = uicontrol('Parent',smaux.smgui.nullpanel,'Style','text',...
        'String','Loops:',...
        'HorizontalAlignment','right',...
        'Position',[5 panYloops 40 15]);
    smaux.smgui.numloops_eth = uicontrol('Parent',smaux.smgui.nullpanel,'Style','edit',...
        'String','1',...
        'Position',[48 panYloops 15 20],...
        'TooltipString','Number of loops',...
        'Callback',@NumLoops);
    
    smaux.smgui.saveloop_sth = uicontrol('Parent',smaux.smgui.nullpanel,'Style','text',...
        'String','Save Loop:',...
        'HorizontalAlignment','left',...
        'Position',[75 panYloops 60 15]);
    smaux.smgui.saveloop_eth = uicontrol('Parent',smaux.smgui.nullpanel,'Style','edit',...
        'String','1',...
        'Position',[135 panYloops 15 20],...
        'TooltipString','Data is saved during this loop. Setting to 1 will save at each point',...
        'Callback',@SaveLoop);
    
    panYcomm = panYloops - 35;
    smaux.smgui.commenttext_sth = uicontrol('Parent',smaux.smgui.nullpanel,'Style','text',...
        'String','Comments:',...
        'HorizontalAlignment','left',...
        'Position',[5 panYcomm 170 20]);
    smaux.smgui.commenttext_eth = uicontrol('Parent',smaux.smgui.nullpanel,'Style','edit',...
        'String','',...
        'FontSize',8,...
        'Position',[5 panYcomm-130 170 130],...
        'HorizontalAlignment','left',...
        'max',20,...
        'Callback',@Comment);
    
    panYDisp = panYcomm - 160;
    %UI Controls for plot selection
    smaux.smgui.oneDplot_sth = uicontrol('Parent',smaux.smgui.nullpanel,'Style','text',...
        'String','1D Plots',...
        'Position',[5 panYDisp 80 20]);
    smaux.smgui.oneDplot_lbh = uicontrol('Parent',smaux.smgui.nullpanel,'Style','listbox',...
        'String',{},...
        'Max',10,...
        'Position',[5 panYDisp-150 80 150],...
        'Callback',@Plot);
    smaux.smgui.twoDplot_sth = uicontrol('Parent',smaux.smgui.nullpanel,'Style','text',...
        'String','2D Plots',...
        'Position',[95 panYDisp 80 20]);
    smaux.smgui.twoDplot_lbh = uicontrol('Parent',smaux.smgui.nullpanel,'Style','listbox',...
        'String',{},...
        'Max',10,...
        'Position',[95 panYDisp-150 80 150],...
        'Callback',@Plot);
    
    panYbuttons = panYDisp - 190;
    %UI Controls to add smscan to collection of scans or measurement queue
    smaux.smgui.toscans_pbh = uicontrol('Parent',smaux.smgui.nullpanel,'Style','pushbutton',...
        'String','TO SCANS',...
        'FontSize',14,...
        'Position', [5 panYbuttons 170 30],...
        'Callback',@ToScans);
        
    smaux.smgui.toqueue_pbh = uicontrol('Parent',smaux.smgui.nullpanel,'Style','pushbutton',...
        'String','TO QUEUE',...
        'FontSize',14,...
        'Position', [5 panYbuttons-30 170 30],...
        'Callback',@ToQueue);
    
    smaux.smgui.smrun_pbh = uicontrol('Parent',smaux.smgui.nullpanel,'Style','pushbutton',...
        'String','RUN',...
        'FontSize',14,...
        'Position',[5 panYbuttons-60 170 30],...
        'BackgroundColor','green',...
        'Callback',@Run);
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %     Programming the GUI     %
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    Update();
    registerSmallGuiWithPptState();
    registerSmallGuiWithDataState();
    set(smaux.smgui.figure1,'Visible','on')

end 


function SaveScan(hObject,eventdata)
    global smscan
    defaultName = "scan.mat";
    if isstruct(smscan) && isfield(smscan, "name") && ~isempty(smscan.name)
        defaultName = string(sanitizeFilename(string(smscan.name))) + ".mat";
    end
    [smscanFile,smscanPath] = uiputfile('*.mat','Save Scan As', char(defaultName));
    if isequal(smscanFile, 0)
        return;
    end
    save(fullfile(smscanPath,smscanFile),'smscan');
end

function LoadScan(hObject,eventdata)
    global smscan
    [smscanFile,smscanPath] = uigetfile('*.mat','Select Scan File');
    if isequal(smscanFile, 0)
        return;
    end
    try
        S = load(fullfile(smscanPath, smscanFile));
    catch
        return;
    end
    if isfield(S, "smscan")
        smscan = S.smscan;
    elseif isfield(S, "scan")
        smscan = S.scan;
    else
        return;
    end
    smscan = smscanSanitizeForBridge(smscan);
    if isempty(smscan)
        return;
    end
    if isfield(smscan,'consts') && ~isfield(smscan.consts,'set')
        for i=1:length(smscan.consts)
            smscan.consts(i).set=1;
        end
    end
    scaninit;
end

function EditRack(hObject,eventdata)
    msgbox("Edit Rack is not implemented in sm1.5. Edit your setup script (e.g., demos/demo.m; debug-only explicit-rack scripts live in tests/).", ...
        "Not Implemented", "help");
end

function loopvars_addchan_pbh_Callback(hObject,eventdata,i)
    global smscan;
    smscan.loops(i).numchans=smscan.loops(i).numchans+1;
    smscan.loops(i).setchan{smscan.loops(i).numchans}='none';
    if isfield(smscan.loops(i), 'setchanranges')
        smscan.loops(i).setchanranges{smscan.loops(i).numchans}=[0 1];
    else
        smscan.loops(i).rng=[0 1];
    end
    makeloopchannelset(i,smscan.loops(i).numchans);
end

function loopcvars_delchan_pbh_Callback(hObject,eventdata,i,j)
global smaux smscan;
    smscan.loops(i).numchans=smscan.loops(i).numchans-1;
    if smscan.loops(i).numchans<0
        smscan.loops(i).numchans=0;
    end
    smscan.loops(i).setchan(j)=[];
    if isfield(smscan.loops(i),'setchanranges')&&(length(smscan.loops(i).setchanranges)>=j)
        smscan.loops(i).setchanranges(j)=[]; 
    end
    makelooppanels;
end

% Callbacks for loop variable edit text boxes (Points, ramptime)
function loopvars_eth_Callback(hObject,eventdata,i,j)
    global smaux smscan;
    obj=smaux.smgui.loopvars_eth(i,j);
    val = str2double(get(obj,'String'));
    if j==1  %number of points being changed
        if (isnan(val) || mod(val,1)~=0 || val<1)
            errordlg('Please enter a positive integer','Invalid Input Value');
            set(obj,'String',smscan.loops(i).npoints);
            return;
        else
            smscan.loops(i).npoints = val;
            for j=1:smscan.loops(i).numchans
                makeloopchannelset(i,j)
            end
        end        
    elseif j==2  %Ramptime being changed
        val = str2double(get(obj,'String'));         
        smscan.loops(i).ramptime=val;
    elseif j==3  %adjust wait time for scan
        val=str2double(get(obj,'String'));
        if (val<0)
            errordlg('Please enter a positive number','Invalid Input Value');
            set(obj,'String','0');
            return;
        else
            smscan.loops(i).waittime=val;
        end
    elseif j==4  %adjust start wait time
        val=str2double(get(obj,'String'));
        if (val<0)
            errordlg('Please enter a positive number','Invalid Input Value');
            set(obj,'String','0');
            return;
        else
            smscan.loops(i).startwait=val;
        end
    end
end


%Callbacks for loop variable channel edit text boxes (channel, min,
%   max, mid, range, step)   
function loopcvars_eth_Callback(hObject,eventdata,i,j,k)
    global smaux smscan smdata bridge;
    obj=smaux.smgui.loopcvars_eth(i,j,k);
    if k==1 % Change the channel being ramped
        % Get the pure scalar channel names (what's shown in dropdown)
        pureScalarChannelNames = getChannelNamesForContext('pure-scalar');
        selectedScalarChannel = pureScalarChannelNames{get(obj,'Value')-1};  % -1 because first option is 'none'
        smscan.loops(i).setchan(j)={selectedScalarChannel};
    elseif k==2 % Change the min value of the channel
        val = str2double(get(obj,'String'));
        smscan.loops(i).setchanranges{j}(1)=val;
    elseif k==3 % Change the max value of the channel
        val = str2double(get(obj,'String'));
        smscan.loops(i).setchanranges{j}(2)=val;
    elseif k==4 %Change the mid value of the channel
        val = str2double(get(obj,'String'));
        range=smscan.loops(i).setchanranges{j}(2)-smscan.loops(i).setchanranges{j}(1);
        smscan.loops(i).setchanranges{j}(1)=val-range/2;
        smscan.loops(i).setchanranges{j}(2)=val+range/2;
    elseif k==5 % Change the range of the channel
        val = str2double(get(obj,'String'));
        mid = (smscan.loops(i).setchanranges{j}(2)+smscan.loops(i).setchanranges{j}(1))/2;
        smscan.loops(i).setchanranges{j}(1)=mid-val/2;
        smscan.loops(i).setchanranges{j}(2)=mid+val/2;
    elseif k==6 % change the stepsize *FOR ALL CHANNELS IN THIS LOOP*
        val = str2double(get(obj,'String'));
        range=smscan.loops(i).setchanranges{j}(2)-smscan.loops(i).setchanranges{j}(1);
        smscan.loops(i).npoints=floor(range/val+1);
        set(smaux.smgui.loopvars_eth(i,1),'String',smscan.loops(i).npoints);
        for c=1:smscan.loops(i).numchans
            makeloopchannelset(i,c)
        end
    end
    makeloopchannelset(i,j);
end


%stored in loops.rng instead of in loops.setchanranges)
function loopcvarsLOCKT_eth_Callback(hObject,eventdata,i,j,k)
    global smaux smscan smdata bridge;
    obj=smaux.smgui.loopcvars_eth(i,j,k);
    if k==1 % Change the channel being ramped
        % Get the pure scalar channel names (what's shown in dropdown)
        pureScalarChannelNames = getChannelNamesForContext('pure-scalar');
        selectedScalarChannel = pureScalarChannelNames{get(obj,'Value')-1};  % -1 because first option is 'none'
        smscan.loops(i).setchan(j)={selectedScalarChannel};
    elseif k==2 % Change the min value of the channel
        val = str2double(get(obj,'String'));
        smscan.loops(i).rng(1)=val;
    elseif k==3 % Change the max value of the channel
        val = str2double(get(obj,'String'));
        smscan.loops(i).rng(2)=val;
    elseif k==4 %Change the mid value of the channel
        val = str2double(get(obj,'String'));
        range=smscan.loops(i).rng(2)-smscan.loops(i).rng(1);
        smscan.loops(i).rng(1)=val-range/2;
        smscan.loops(i).rng(2)=val+range/2;
    elseif k==5 % Change the range of the channel
        val = str2double(get(obj,'String'));
        mid = (smscan.loops(i).rng(2)+smscan.loops(i).rng(1))/2;
        smscan.loops(i).rng(1)=mid-val/2;
        smscan.loops(i).rng(2)=mid+val/2; 
    elseif k==6 % change the stepsize 
        val = str2double(get(obj,'String'));
        range=smscan.loops(i).rng(2)-smscan.loops(i).rng(1);
        smscan.loops(i).npoints=floor(range/val+1);
        set(smaux.smgui.loopvars_eth(i,1),'String',smscan.loops(i).npoints);
        for c=1:smscan.loops(i).numchans
            makeloopchannelset(i,c)
        end
    end
    makeloopchannelset(i,j);
end

%Callback for getchannel pmh
function GetChannel(hObject,eventdata,i,j)
global smaux smscan smdata bridge;
    val = get(smaux.smgui.loopvars_getchans_pmh(i,j),'Value');
    if val==1
        smscan.loops(i).getchan(j)=[];
    else
        popupStrings = get(smaux.smgui.loopvars_getchans_pmh(i,j), "String");
        if iscell(popupStrings)
            popupStrings = string(popupStrings);
        end
        if ischar(popupStrings)
            popupStrings = string(popupStrings);
        end
        if val <= numel(popupStrings)
            selectedVectorChannel = popupStrings(val);
            if selectedVectorChannel == "none"
                smscan.loops(i).getchan(j) = [];
            else
                % Store the vector channel name - setplotchoices will handle expansion
                smscan.loops(i).getchan{j} = selectedVectorChannel;
            end
        else
            smscan.loops(i).getchan(j) = [];
        end
    end
    makelooppanels;
end

%Callback for the constants pmh
function ConstMenu(hObject,eventdata,i)
global smaux smscan smdata bridge;
    val=get(smaux.smgui.consts_pmh(i),'Value');
    if val==1
        smscan.consts(i)=[];
    else
        % Get the pure scalar channel names (what's shown in dropdown)
        pureScalarChannelNames = getChannelNamesForContext('pure-scalar');
        selectedScalarChannel = pureScalarChannelNames{val-1};  % -1 because first option is 'none'
        
        smscan.consts(i).setchan = selectedScalarChannel;
        if ~isfield(smscan.consts(i),'val')
            smscan.consts(i).val=0;
        end
        if ~isfield(smscan.consts(i),'set')
            smscan.consts(i).set=1;
        end
    end
    makeconstpanel;
end

%Callback for the constants eth
function ConstTXT(hObject,eventdata,i)
global smaux smscan;
    val = str2double(get(smaux.smgui.consts_eth(i),'String'));
    if (isnan(val))
        errordlg('Please enter a real number','Invalid Input Value');
        set(smaux.smgui.consts_eth(i),'String',0);
        return;
    end
    smscan.consts(i).val=val;
end

% Callback for constants checkboxes
function SetConsts(hObject,eventdata,i)
global smaux smscan;
    smscan.consts(i).set = get(smaux.smgui.setconsts_cbh(i),'Value');  
end

%Callback for update constants pushbutton
function UpdateConstants(varargin)
    global smaux smscan engine;

    % Constants channel dropdowns are scalar-only channelFriendlyNames.
    if ~exist("engine", "var") || isempty(engine) || ~isa(engine, "measurementEngine")
        error("smgui_small:MissingEngine", "measurementEngine not found. Please run smready(...) first.");
    end

    if ~isfield(smscan, "consts") || isempty(smscan.consts)
        return;
    end

    consts = smscan.consts;
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
        i = getIdx(k);
        smscan.consts(i).val = newvals(k);
        if abs(floor(log10(newvals(k)))) > 3
            set(smaux.smgui.consts_eth(i), "String", sprintf("%0.1e", newvals(k)));
        else
            set(smaux.smgui.consts_eth(i), "String", round(1000 * newvals(k)) / 1000);
        end
    end
end

 % Callback for data file location pushbutton
function SavePath(varargin)
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
        smdatapathUpdateGlobalState("small", smaux.datadir);
        smdatapathApplyStateToGui("small");
    end
end

% Callback for changing title of scan
function ScanTitle(varargin)
    global smaux smscan;
    rawName = get(smaux.smgui.scantitle_eth,'String');
    smscan.name = sanitizeFilename(rawName);
    % Update the textbox to show sanitized name
    if ~strcmp(rawName, smscan.name)
        set(smaux.smgui.scantitle_eth,'String', smscan.name);
    end
end


%Callback for filename pushbutton
function FileName(varargin)
global smaux smscan bridge;
    [savedataFile,savedataPath] = uiputfile('*.mat','Save Data As');
    if savedataPath ~= 0
        rootPath = string(pwd);
        if exist("bridge", "var") && ~isempty(bridge) && isobject(bridge) && isprop(bridge, "experimentRootPath")
            if strlength(string(bridge.experimentRootPath)) == 0
                bridge.experimentRootPath = pwd;
            end
            rootPath = string(bridge.experimentRootPath);
        end

        pickedPath = string(savedataPath);
        targetPath = pickedPath;
        if strlength(rootPath) > 0
            if endsWith(pickedPath, filesep)
                pickedPath = extractBefore(pickedPath, strlength(pickedPath));
            end
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
        smdatapathUpdateGlobalState("small", smaux.datadir);
        smdatapathApplyStateToGui("small");

        savedataFile=savedataFile(1:end-4); %crop off .mat
        separators=strfind(savedataFile,'_');
        if separators
            runstring=savedataFile(separators(end)+1:end);
            rundouble=str2double(runstring);
            if ~isnan(rundouble)
                runint=uint16(rundouble);
                smrunUpdateGlobalState('small', double(runint));
                smrunApplyStateToGui('small');
                savedataFile=savedataFile(1:separators(end)-1); %crop off runstring
            end
        end
        set(smaux.smgui.filename_eth,'String',savedataFile);
    end
end

% Callback for ppt file location pushbutton
function SavePPT(varargin)
global smaux bridge;
    [pptFile, ~] = uiputfile('*.ppt','Append to Presentation');
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
    checkboxValue = false;
    if isstruct(smaux) && isfield(smaux, 'smgui') && isstruct(smaux.smgui) ...
            && isfield(smaux.smgui, 'appendppt_cbh') && ishandle(smaux.smgui.appendppt_cbh)
        checkboxValue = logical(get(smaux.smgui.appendppt_cbh, 'Value'));
    end
    smpptUpdateGlobalState('small', checkboxValue, selectedFile);
    smpptApplyStateToGui('small');
end

function AppendPptToggle(varargin)
    global smaux
    checkboxValue = false;
    if isstruct(smaux) && isfield(smaux, 'smgui') && isstruct(smaux.smgui) ...
            && isfield(smaux.smgui, 'appendppt_cbh') && ishandle(smaux.smgui.appendppt_cbh)
        checkboxValue = logical(get(smaux.smgui.appendppt_cbh, 'Value'));
    end
    smpptUpdateGlobalState('small', checkboxValue);
    smpptApplyStateToGui('small');
end

function syncScanPptFromGUI()
    global smaux
    checkboxValue = false;
    if isstruct(smaux) && isfield(smaux, 'smgui') && isstruct(smaux.smgui) ...
            && isfield(smaux.smgui, 'appendppt_cbh') && ishandle(smaux.smgui.appendppt_cbh)
        checkboxValue = logical(get(smaux.smgui.appendppt_cbh, 'Value'));
    end
    smpptUpdateGlobalState('small', checkboxValue);
    smpptApplyStateToGui('small');
end
    
%callback for comment text
function Comment(varargin)
global smaux smscan;
    smscan.comments = (get(smaux.smgui.commenttext_eth,'String'));
end

% Callback for updating run number
function RunNumber(varargin)
    global smaux;
    strValue = get(smaux.smgui.runnumber_eth,'String');
    if isempty(strValue)
        set(smaux.smgui.autoincrement_cbh,'Value',0);
        smrunUpdateGlobalState('small', []);
    else
        val = str2double(strValue);
        if ~isnan(val) && isfinite(val) && val>=0 && val<=999
            smrunUpdateGlobalState('small', val);
        else
            errordlg('Please enter an integer in [000 999]','Bad Run Number');
            smrunUpdateGlobalState('small', []);
        end
    end
    smrunApplyStateToGui('small');
end

% Callback for updating number of loops
function NumLoops(hObject,eventdata)
    global smaux smscan;
    val = str2double(get(smaux.smgui.numloops_eth,'String'));
    if (isnan(val) || mod(val,1)~=0 || val<1)
        errordlg('Please enter a positive integer','Invalid Input Value');
        numloops = length(smscan.loops);
        set(smaux.smgui.numloops_eth,'String',numloops);
        return;
    else
        if length(smscan.loops) > val
            smscan.loops = smscan.loops(1:val);
        else
            for i=length(smscan.loops)+1:val
                smscan.loops(i).npoints=101;
                smscan.loops(i).rng=[0 1];
                smscan.loops(i).getchan={};
                smscan.loops(i).setchan={'none'};
                smscan.loops(i).setchanranges={[0 1]};
                smscan.loops(i).ramptime=[];
                smscan.loops(i).numchans=0;
                smscan.loops(i).waittime=0;
            end
        end
    end
       
    makelooppanels;
    makeconstpanel;
end

% Callback for updating save loop
function SaveLoop(hObject,eventdata)
    global smaux smscan;
    val = str2double(get(smaux.smgui.saveloop_eth,'String'));
    if (isnan(val) || mod(val,1)~=0 || val<1)
        errordlg('Please enter a positive integer','Invalid Input Value');
        set(smaux.smgui.saveloop_eth,'String',smscan.saveloop);
        return;
    else
        smscan.saveloop = val;
    end
       
    makelooppanels;
    makeconstpanel;
end

%callback for plot list box objects
function Plot(varargin)
    global smaux smscan;
    
    % Build plot choices using same logic as setplotchoices
    [plotchoicesAll, plotchoices2d] = buildPlotChoices();
    
    vals1d = get(smaux.smgui.oneDplot_lbh,'Val');
    vals2d = get(smaux.smgui.twoDplot_lbh,'Val');
    dispEntries = struct('loop', {}, 'channel', {}, 'dim', {}, 'name', {});
    entryIndex = 0;
    for i = 1:length(vals1d)
        chanIdx = vals1d(i);
        if chanIdx < 1 || chanIdx > numel(plotchoicesAll.string)
            continue;
        end
        entryIndex = entryIndex + 1;
        dispEntries(entryIndex).loop = plotchoicesAll.loop(chanIdx);
        dispEntries(entryIndex).channel = chanIdx;
        dispEntries(entryIndex).dim = 1;
        dispEntries(entryIndex).name = string(plotchoicesAll.string{chanIdx});
    end
    for i = 1:length(vals2d)
        local_idx = vals2d(i);
        if local_idx < 1 || local_idx > numel(plotchoices2d.string)
            continue;
        end
        entryIndex = entryIndex + 1;
        dispEntries(entryIndex).loop = plotchoices2d.loop(local_idx) + 1;
        dispEntries(entryIndex).channel = plotchoices2d.full_index(local_idx);
        dispEntries(entryIndex).dim = 2;
        dispEntries(entryIndex).name = string(plotchoices2d.string{local_idx});
    end
    smscan.disp = dispEntries;
    
    setplotchoices;
end

%populates plot choices
function setplotchoices(varargin)
    global smscan smaux;
        [plotchoicesAll, plotchoices2d] = buildPlotChoices();
        set(smaux.smgui.oneDplot_lbh,'String',plotchoicesAll.string);       
        set(smaux.smgui.twoDplot_lbh,'String',plotchoices2d.string);       
        
        % Disable 2D plots selection when there is only 1 loop
        numloops = length(smscan.loops);
        if numloops <= 1
            set(smaux.smgui.twoDplot_lbh,'Enable','off');
            set(smaux.smgui.twoDplot_sth,'Enable','off');
            % Clear any existing 2D plot selections when disabled
            set(smaux.smgui.twoDplot_lbh,'Val',[]);
            % Remove any 2D display entries from smscan.disp
            if isfield(smscan, 'disp') && ~isempty(smscan.disp)
                keep_indices = [];
                for k = 1:length(smscan.disp)
                    if isfield(smscan.disp(k), 'dim') && smscan.disp(k).dim ~= 2
                        keep_indices = [keep_indices k];
                    end
                end
                if ~isempty(keep_indices)
                    smscan.disp = smscan.disp(keep_indices);
                else
                    smscan.disp = [];
                end
            end
        else
            set(smaux.smgui.twoDplot_lbh,'Enable','on');
            set(smaux.smgui.twoDplot_sth,'Enable','on');
        end
        
        plotNames = string(plotchoicesAll.string);
        newoneDvals = [];
        newtwoDvals = [];
        full_to_2d = zeros(1, numel(plotchoicesAll.string));
        if ~isempty(plotchoices2d.full_index)
            full_to_2d(plotchoices2d.full_index) = 1:numel(plotchoices2d.full_index);
        end
        valid_disp_mask = true(1, length(smscan.disp));
        for i=1:length(smscan.disp)
            dispName = "";
            if isfield(smscan.disp, "name")
                dispName = string(smscan.disp(i).name);
            end
            if strlength(dispName) == 0
                channel_idx = smscan.disp(i).channel;
                if channel_idx >= 1 && channel_idx <= numel(plotchoicesAll.string)
                    dispName = plotNames(channel_idx);
                end
            end
            if strlength(dispName) == 0
                valid_disp_mask(i) = false;
                continue;
            end
            channel_idx = find(plotNames == dispName, 1);
            if isempty(channel_idx)
                valid_disp_mask(i) = false;
                continue;
            end
            smscan.disp(i).name = dispName;
            smscan.disp(i).channel = channel_idx;
            if smscan.disp(i).dim==1
                newoneDvals = [newoneDvals channel_idx];
            elseif smscan.disp(i).dim == 2
                mapped_idx = full_to_2d(channel_idx);
                if mapped_idx > 0
                    newtwoDvals = [newtwoDvals mapped_idx];
                else
                    valid_disp_mask(i) = false;
                end
            end
        end
        if any(~valid_disp_mask)
            smscan.disp = smscan.disp(valid_disp_mask);
        end
        newoneDvals = sort(newoneDvals);
        newtwoDvals = sort(newtwoDvals);
        maxOneD = numel(plotchoicesAll.string);
        maxTwoD = numel(plotchoices2d.string);
        if maxOneD == 0
            newoneDvals = [];
        else
            newoneDvals = newoneDvals(newoneDvals >= 1 & newoneDvals <= maxOneD);
        end
        if maxTwoD == 0
            newtwoDvals = [];
        else
            newtwoDvals = newtwoDvals(newtwoDvals >= 1 & newtwoDvals <= maxTwoD);
        end
        set(smaux.smgui.oneDplot_lbh,'Val',newoneDvals);
        set(smaux.smgui.twoDplot_lbh,'Val',newtwoDvals);
end

function [plotchoicesAll, plotchoices2d] = buildPlotChoices()
    global smscan;

    allgetchans={smscan.loops.getchan};
    plotchoicesAll.string={};
    plotchoicesAll.loop=[];
    plotchoicesAll.full_index=[];

    full_idx = 0;
    for i=1:length(allgetchans)
        for j=1:length(allgetchans{i})
            % Convert vector channel names to scalar names for plotting
            vectorChanName = allgetchans{i}{j};
            scalarChanNames = convertVectorToScalarNames(vectorChanName);
            for k=1:length(scalarChanNames)
                full_idx = full_idx + 1;
                plotchoicesAll.string = [plotchoicesAll.string scalarChanNames(k)];
                plotchoicesAll.loop=[plotchoicesAll.loop i];
                plotchoicesAll.full_index=[plotchoicesAll.full_index full_idx];
            end
        end
    end

    numloops = length(smscan.loops);
    mask2d = plotchoicesAll.loop < numloops;
    plotchoices2d.string = plotchoicesAll.string(mask2d);
    plotchoices2d.loop = plotchoicesAll.loop(mask2d);
    plotchoices2d.full_index = find(mask2d);
end

% Callback for running the scan (call to smrun)
function Run(varargin)
    global smaux smscan engine;

    syncScanPptFromGUI();

    filestring = get(smaux.smgui.filename_eth,'String');
    if isempty(filestring)
        FileName;
        filestring = get(smaux.smgui.filename_eth,'String');
    end
    if isempty(filestring)
        error("smgui_small:MissingFilename", ...
            "A base filename must be selected before running.");
    end

    if ~isfield(smaux, 'datadir') || isempty(smaux.datadir)
        smaux.datadir = smdatapathDefaultPath();
    end
    if ~exist(smaux.datadir, "dir")
        mkdir(smaux.datadir);
    end
    smdatapathUpdateGlobalState('small', smaux.datadir);
    smdatapathApplyStateToGui('small');

    % Sync scan name from the title textbox (don't overwrite with filename).
    smscan.name = sanitizeFilename(get(smaux.smgui.scantitle_eth, 'String'));

    if ~exist("engine", "var") || isempty(engine) || ~isa(engine, "measurementEngine")
        error("smgui_small:MissingEngine", "measurementEngine not found. Please run smready(...) first.");
    end

    engine.run(smscan, "", "safe");

end

% Callback to send smscan to smaux.scans
function ToScans(varargin)
    global smaux smscan
    try
        syncScanPptFromGUI();
        % Safety net: ensure scan name is sanitized before sending to queue GUI
        if isfield(smscan, 'name')
            smscan.name = sanitizeFilename(smscan.name);
        end
        smaux.scans{end+1}=smscan;
        sm
        sm_Callback('UpdateToGUI');
    catch ME
        % Create detailed error message
        errorMsg = sprintf('Error in ToScans:\n\n%s\n\nFile: %s\nLine: %d\n\nStack trace:\n', ...
            ME.message, ME.stack(1).file, ME.stack(1).line);
        
        % Add stack trace details
        for i = 1:min(3, length(ME.stack))
            errorMsg = sprintf('%s%d. %s (line %d)\n', errorMsg, i, ME.stack(i).name, ME.stack(i).line);
        end
        
        % Show error dialog
        errordlg(errorMsg, 'ToScans Error', 'modal');
    end
end

% Callback to send smscan to smaux.queue
function ToQueue(varargin)
    global smaux smscan
    try
        syncScanPptFromGUI();
        % Safety net: ensure scan name is sanitized before sending to queue
        if isfield(smscan, 'name')
            smscan.name = sanitizeFilename(smscan.name);
        end
        smaux.smq{end+1}=smscan;
        sm
        sm_Callback('UpdateToGUI');
    catch ME
        % Create detailed error message
        errorMsg = sprintf('Error in ToQueue:\n\n%s\n\nFile: %s\nLine: %d\n\nStack trace:\n', ...
            ME.message, ME.stack(1).file, ME.stack(1).line);
        
        % Add stack trace details
        for i = 1:min(3, length(ME.stack))
            errorMsg = sprintf('%s%d. %s (line %d)\n', errorMsg, i, ME.stack(i).name, ME.stack(i).line);
        end
        
        % Show error dialog
        errordlg(errorMsg, 'ToQueue Error', 'modal');
    end
end

% updates the GUI components
function Update(varargin)
    global smaux smscan smdata;

    if ~isstruct(smscan)
        smscan.loops(1).npoints=100;
        smscan.loops(1).rng=[0 1];
        smscan.loops(1).getchan={};
        smscan.loops(1).setchan={};
        smscan.loops(1).setchanranges={};
        smscan.loops(1).ramptime=[];
        smscan.loops(1).numchans=0;
        smscan.loops(1).waittime=0;
        smscan.saveloop=1;
        smscan.disp(1).loop=[];
        smscan.disp(1).channel=[];
        smscan.disp(1).dim=[];
        smscan.disp(1).name="";
        smscan.consts=[];
        smscan.comments='';
        smscan.name='';
        scaninit
    else
        scaninit;
    end
    
    if isstruct(smaux)
        if ~isfield(smaux, 'datasavefile')
            smaux.datasavefile = 'log';
        end

        set(smaux.smgui.filename_eth,'String', smaux.datasavefile);

        %if a directory path has not been set, use current folder + \data.
        if ~isfield(smaux,'datadir') || isempty(smaux.datadir)
            smaux.datadir = smdatapathDefaultPath();
        end
        if ~exist(smaux.datadir, "dir")
            mkdir(smaux.datadir);
        end

        currentPath = smdatapathGetState();
        if ~strcmp(currentPath, smaux.datadir)
            smdatapathUpdateGlobalState('small', smaux.datadir);
        else
            smdatapathApplyStateToGui('small');
        end
        
        smrunApplyStateToGui('small');
    end
    registerSmallGuiWithPptState();
    smpptApplyStateToGui('small');
    registerSmallGuiWithDataState();
    smdatapathApplyStateToGui('small');
    registerSmallGuiWithRunState();
    smrunApplyStateToGui('small');
end

function scaninit(varargin)
        global smaux smscan ;
        numloops = length(smscan.loops);
        set(smaux.smgui.numloops_eth,'String',numloops);
        set(smaux.smgui.saveloop_eth,'String',smscan.saveloop);
        if isfield(smscan,'name')
            set(smaux.smgui.scantitle_eth,'String',smscan.name);
        end
        for i=1:length(smscan.loops)
            smscan.loops(i).numchans=length(smscan.loops(i).setchan);
        end
         if ~isfield(smscan,'consts')
             smscan.consts = [];
         end
        if isfield(smscan,'comments')
            set(smaux.smgui.commenttext_eth,'String',smscan.comments);
        else
            smscan.comments='';
        end
        makeconstpanel;
        makelooppanels;
        setplotchoices;
        
end

% make or delete looppanels
% postcon: length(loop_panels_ph) = length(smscan.loops) = numloops
function makelooppanels(varargin)
    global smaux smscan smdata;
    numloops = length(smscan.loops);
    
    %Set constants panel to below filename panel
    posData = get(smaux.smgui.scan_constants_ph,'position');
    height = 190; %was 290
    margin = 10;
    panel1position=[180 posData(2)-margin 700 height];
    

    for i=1:length(smaux.smgui.loop_panels_ph)
        delete(smaux.smgui.loop_panels_ph(i));
    end
    smaux.smgui.loop_panels_ph=[];

    for i = (length(smaux.smgui.loop_panels_ph)+1):numloops % display data from existing loops
        smaux.smgui.loop_panels_ph(i) = uipanel('Parent',smaux.smgui.nullpanel,...
            'Units','pixels',...
            'Position',panel1position+[0*(i) -190*(i) -0*(i) 0]);

        % for new loops only
        if i>length(smscan.loops)
            smscan.loops(i).npoints=101;
            smscan.loops(i).rng=[0 1];
            smscan.loops(i).getchan=[];
            smscan.loops(i).setchan={'none'};
            smscan.loops(i).setchanranges={[0 1]};
            smscan.loops(i).ramptime=[];
            smscan.loops(i).numchans=0;
            smscan.loops(i).waittime=0;
        end

        %Pushbutton for adding setchannels to the loop
        smaux.smgui.loopvars_addchan_pbh(i) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
            'Style','pushbutton',...
            'String','Add Channel',...
            'Position',[25 147 100 20],...
            'Callback',{@loopvars_addchan_pbh_Callback,i});

        %Number of points in loop
        if isfield(smscan.loops(i),'npoints')
            numpoints(i)=smscan.loops(i).npoints;
        else
            numpoints(i)=nan;
        end
        smaux.smgui.loopvars_sth(i,1) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
            'Style','text',...
            'String','Points:',...
            'HorizontalAlignment','right',...
            'Position',[165 147 50 20]);
        smaux.smgui.loopvars_eth(i,1) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
            'Style','edit',...
            'String',numpoints(i),...
            'HorizontalAlignment','center',...
            'Position',[215 152 50 20],...
            'Callback',{@loopvars_eth_Callback,i,1});
        
        %Step Time
        smaux.smgui.loopvars_sth(i,2) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
            'Style','text',...
            'String','Step time:',...
            'HorizontalAlignment','right',...
            'Position',[435 147 55 20]);
        smaux.smgui.loopvars_eth(i,2) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
            'Style','edit',...
            'String',smscan.loops(i).ramptime,...
            'ToolTipString','(s) Time when ramping between each point',...
            'HorizontalAlignment','center',...
            'Position',[495 152 55 20],...
            'Callback',{@loopvars_eth_Callback,i,2});

        %Wait times            
        smaux.smgui.loopvars_sth(i,3) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
            'Style','text',...
            'String','Wait (s):',...
            'HorizontalAlignment','right',...
            'Position',[555 147 55 20]);
        smaux.smgui.loopvars_eth(i,3) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
            'Style','edit',...
            'String',0,...
            'TooltipString','(s) Wait before getting data',...
            'HorizontalAlignment','center',...
            'Position',[615 152 55 20],...
            'Callback',{@loopvars_eth_Callback,i,3});
        if isfield(smscan.loops(i),'waittime')
            set(smaux.smgui.loopvars_eth(i,3),'String',smscan.loops(i).waittime);
        end
        
        %Start wait time
        smaux.smgui.loopvars_sth(i,4) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
            'Style','text',...
            'String','Start Wait:',...
            'HorizontalAlignment','right',...
            'Position',[335 147 55 20]);
        smaux.smgui.loopvars_eth(i,4) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
            'Style','edit',...
            'String',0,...
            'ToolTipString','After setting first value of loop, waits this amount of time (s)',...
            'HorizontalAlignment','center',...
            'Position',[395 152 35 20],...
            'Callback',{@loopvars_eth_Callback,i,4});
        if isfield(smscan.loops(i),'startwait')
            set(smaux.smgui.loopvars_eth(i,4),'String',smscan.loops(i).startwait);
        end
        

        %Add UI controls for set channels
        for j=1:smscan.loops(i).numchans
            makeloopchannelset(i,j);
        end


        %Add popup menus for get channels 
        smaux.smgui.loopvars_sth(i,4) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
            'Style','text',...
            'String','Record:',...
            'HorizontalAlignment','center',...
            'Position',[5 35 50 20]);
        makeloopgetchans(i);
        setplotchoices;
    end


    %delete loops   
    for i = (numloops+1):length(smaux.smgui.loop_panels_ph)       
        delete(smaux.smgui.loop_panels_ph(i));            
    end
    smscan.loops = smscan.loops(1:numloops);

    smaux.smgui.loop_panels_ph=smaux.smgui.loop_panels_ph(1:numloops);
    smaux.smgui.loopvars_eth=smaux.smgui.loopvars_eth(1:numloops,:);
    smaux.smgui.loopvars_sth=smaux.smgui.loopvars_sth(1:numloops,:);


    %label the loops
    set(smaux.smgui.loop_panels_ph(numloops),'Title',sprintf('Loop %d (outer)',numloops));
    set(smaux.smgui.loop_panels_ph(1),'Title',sprintf('Loop %d (inner)',1));
    for k = 2:numloops-1
        set(smaux.smgui.loop_panels_ph(k),'Title',sprintf('Loop %d',k));
    end      
end

% makes ui objects for setchannel j on loop i                
function makeloopchannelset(i,j) 
    global smaux smscan smdata;
    size = get(smaux.smgui.loop_panels_ph(i),'Position');
    pos = [5 size(4)-50-25*j 0 0];
    w = [100 40 40 40 40 40]; % widths
    h = [20 20 20 20 20 20 20 20 20 20 50]; % heights
    s = 95; %spacing

    % button to delete this setchannel
    smaux.smgui.loopcvars_delchan_pbh(i,j) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
        'Style','pushbutton',...
        'String','Delete',...
        'Position',pos+[0 0 50 20],...
        'Callback',{@loopcvars_delchan_pbh_Callback,i,j});

    % select channel being ramped
    channelnames = getChannelNamesForContext('pure-scalar');  % Use pure scalar names for set channels
    smaux.smgui.loopcvars_sth(i,j,1) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
        'Style','text',...
        'String','Channel:',...
        'HorizontalAlignment','right',...
        'Position',pos+[55 -5 45 h(1)]);

    if strcmp('none', smscan.loops(i).setchan{j})
        chanval=1;
    else
        try
            % Find position in dropdown list, not smdata.channels indices  
            chanName = smscan.loops(i).setchan{j};
            chanval = find(strcmp(channelnames, chanName));
            if isempty(chanval)
                chanval = 1; % Default to 'none'
            else
                chanval = chanval + 1; % +1 for 'none' option in popup
            end
        catch ME
            % Build detailed error message for channel lookup
            chanName = smscan.loops(i).setchan{j};
            if iscell(chanName)
                chanNameStr = sprintf('{%s}', strjoin(string(chanName), ', '));
            else
                chanNameStr = string(chanName);
            end
            
            debugMsg = sprintf(['CHANNEL LOOKUP FAILED\n\n' ...
                               'Channel: ''%s''\n' ...
                               'Class: %s\n' ...
                               'Error: %s\n\n' ...
                               'Available channels:\n'], ...
                               chanNameStr, class(chanName), ME.message);
            
            % Add list of available channels
            if exist('smdata', 'var') && isfield(smdata, 'channels') && ~isempty(smdata.channels)
                for k = 1:min(10, length(smdata.channels))  % Show first 10 channels
                    debugMsg = [debugMsg sprintf('  %d: %s\n', k, smdata.channels(k).name)];
                end
                if length(smdata.channels) > 10
                    debugMsg = [debugMsg sprintf('  ... and %d more channels', length(smdata.channels) - 10)];
                end
            else
                debugMsg = [debugMsg '  No channels available - check instrument setup'];
            end
            
            errordlg(debugMsg, 'Channel Lookup Error - Detailed Diagnostics');
            chanval=1;
        end
    end
    smaux.smgui.loopcvars_eth(i,j,1) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
        'Style','popupmenu',...
        'String',['none' channelnames],...
        'Value',chanval,...
        'HorizontalAlignment','center',...
        'Position',pos+[105 0 w(1) h(1)],...
        'Callback',{@loopcvars_eth_Callback,i,j,1});

    if isfield(smscan.loops(i), 'setchanranges')
        if iscell(smscan.loops(i).setchanranges)
            %minimum
            smaux.smgui.loopcvars_sth(i,j,2) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
                'Style','text',...
                'String','Min:',...
                'HorizontalAlignment','right');
            smaux.smgui.loopcvars_eth(i,j,2) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
                'Style','edit',...
                'String',smscan.loops(i).setchanranges{j}(1),...
                'HorizontalAlignment','center',...
                'Callback',{@loopcvars_eth_Callback,i,j,2});

            %max
            smaux.smgui.loopcvars_sth(i,j,3) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
                'Style','text',...
                'String','Max:',...
                'HorizontalAlignment','right');
            smaux.smgui.loopcvars_eth(i,j,3) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
                'Style','edit',...
                'String',smscan.loops(i).setchanranges{j}(2),...
                'HorizontalAlignment','center',...
                'Callback',{@loopcvars_eth_Callback,i,j,3});

            %mid
            smaux.smgui.loopcvars_sth(i,j,4) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
                'Style','text',...
                'String','Mid:',...
                'HorizontalAlignment','right');
            smaux.smgui.loopcvars_eth(i,j,4) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
                'Style','edit',...
                'String',mean(smscan.loops(i).setchanranges{j}),...
                'HorizontalAlignment','center',...
                'Callback',{@loopcvars_eth_Callback,i,j,4});

            %range
            smaux.smgui.loopcvars_sth(i,j,5) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
                'Style','text',...
                'String','Range:',...
                'HorizontalAlignment','right');
            smaux.smgui.loopcvars_eth(i,j,5) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
                'Style','edit',...
                'String',smscan.loops(i).setchanranges{j}(2)-smscan.loops(i).setchanranges{j}(1),...
                'HorizontalAlignment','center',...
                'Callback',{@loopcvars_eth_Callback,i,j,5});

            %stepsize
            smaux.smgui.loopcvars_sth(i,j,6) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
                'Style','text',...
                'String','Step:',...
                'HorizontalAlignment','right');
            smaux.smgui.loopcvars_eth(i,j,6) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
                'Style','edit',...
                'String',(smscan.loops(i).setchanranges{j}(2)-smscan.loops(i).setchanranges{j}(1))/(smscan.loops(i).npoints-1),...
                'HorizontalAlignment','center',...
                'Callback',{@loopcvars_eth_Callback,i,j,6});       
        
            for k=2:6
                set(smaux.smgui.loopcvars_sth(i,j,k),'Position',pos+[s*k-45+60 -5 w(k) h(k)]);
                set(smaux.smgui.loopcvars_eth(i,j,k),'Position',pos+[s*k+60 0 w(k) h(k)]);            
            end
        end
    elseif j==1 % First setchan when using loop range instead of per-channel ranges
         %minimum
        smaux.smgui.loopcvars_sth(i,j,2) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
            'Style','text',...
            'String','Min:',...
            'HorizontalAlignment','right');
        smaux.smgui.loopcvars_eth(i,j,2) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
            'Style','edit',...
            'String',smscan.loops(i).rng(1),...
            'HorizontalAlignment','center',...
            'Callback',{@loopcvarsLOCKT_eth_Callback,i,j,2});

        %max
        smaux.smgui.loopcvars_sth(i,j,3) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
            'Style','text',...
            'String','Max:',...
            'HorizontalAlignment','right');
        smaux.smgui.loopcvars_eth(i,j,3) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
            'Style','edit',...
            'String',smscan.loops(i).rng(2),...
            'HorizontalAlignment','center',...
            'Callback',{@loopcvarsLOCKT_eth_Callback,i,j,3});

        %mid
        smaux.smgui.loopcvars_sth(i,j,4) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
            'Style','text',...
            'String','Mid:',...
            'HorizontalAlignment','right');
        smaux.smgui.loopcvars_eth(i,j,4) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
            'Style','edit',...
            'String',mean(smscan.loops(i).rng),...
            'HorizontalAlignment','center',...
            'Callback',{@loopcvarsLOCKT_eth_Callback,i,j,4});

        %range
        smaux.smgui.loopcvars_sth(i,j,5) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
            'Style','text',...
            'String','Range:',...
            'HorizontalAlignment','right');
        smaux.smgui.loopcvars_eth(i,j,5) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
            'Style','edit',...
            'String',smscan.loops(i).rng(2)-smscan.loops(i).rng(1),...
            'HorizontalAlignment','center',...
            'Callback',{@loopcvarsLOCKT_eth_Callback,i,j,5});

        %stepsize
        smaux.smgui.loopcvars_sth(i,j,6) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
            'Style','text',...
            'String','Step:',...
            'HorizontalAlignment','right');
        smaux.smgui.loopcvars_eth(i,j,6) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
            'Style','edit',...
            'String',(smscan.loops(i).rng(2)-smscan.loops(i).rng(1))/(smscan.loops(i).npoints-1),...
            'HorizontalAlignment','center',...
            'Callback',{@loopcvarsLOCKT_eth_Callback,i,j,6});       

        for k=2:6
            set(smaux.smgui.loopcvars_sth(i,j,k),'Position',pos+[s*k-45+60 -5 w(k) h(k)]);
            set(smaux.smgui.loopcvars_eth(i,j,k),'Position',pos+[s*k+60 0 w(k) h(k)]);            
        end
    end     


end

% Make the getchannel UI popup objects for loop i
function makeloopgetchans(i)
    global smscan smaux smdata;
    numgetchans=length(smscan.loops(i).getchan);
    %smaux.smgui.loopvars_getchans_pmh=[];  %JDSY 7/1/9/2011
    channelnames = getChannelNamesForContext('vector');  % Use vector names for get channels
    channelnames_str = string(channelnames);
    channelnames_str = channelnames_str(:);

    selected_names = string.empty(1, 0);
    for loopIdx = 1:length(smscan.loops)
        loopGetchans = smscan.loops(loopIdx).getchan;
        if isempty(loopGetchans)
            continue;
        end
        for chanIdx = 1:length(loopGetchans)
            chanName = loopGetchans{chanIdx};
            if isempty(chanName)
                continue;
            end
            selected_names(end+1) = string(chanName);
        end
    end

    for j=1:numgetchans
        try
            % Find position in dropdown list, not smdata.channels indices
            chanName = smscan.loops(i).getchan{j};
            current_name = string(chanName);
            available_names = setdiff(channelnames_str, selected_names, "stable");
            available_names = available_names(:);
            if ~isempty(current_name)
                if ~any(available_names == current_name)
                    available_names = [current_name; available_names];
                end
            end

            chanval = find(available_names == current_name);
            if isempty(chanval)
                chanval = 1; % Default to 'none'
            else
                chanval = chanval + 1; % +1 for 'none' option in popup
            end
        catch ME
            % Build detailed error message for getchan
            chanName = smscan.loops(i).getchan{j};
            if iscell(chanName)
                chanNameStr = sprintf('{%s}', strjoin(string(chanName), ', '));
            else
                chanNameStr = string(chanName);
            end
            
            debugMsg = sprintf(['GET CHANNEL LOOKUP FAILED\n\n' ...
                               'Channel: ''%s''\n' ...
                               'Class: %s\n' ...
                               'Error: %s\n\n' ...
                               'Available channels:\n'], ...
                               chanNameStr, class(chanName), ME.message);
            
            % Add list of available channels
            if exist('smdata', 'var') && isfield(smdata, 'channels') && ~isempty(smdata.channels)
                for k = 1:min(10, length(smdata.channels))  % Show first 10 channels
                    debugMsg = [debugMsg sprintf('  %d: %s\n', k, smdata.channels(k).name)];
                end
                if length(smdata.channels) > 10
                    debugMsg = [debugMsg sprintf('  ... and %d more channels', length(smdata.channels) - 10)];
                end
            else
                debugMsg = [debugMsg '  No channels available - check instrument setup'];
            end
            
            errordlg(debugMsg, 'Get Channel Lookup Error - Detailed Diagnostics');
            chanval=1;
        end
        smaux.smgui.loopvars_getchans_pmh(i,j) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
            'Style','popupmenu',...
            'String',["none"; available_names(:)],...
            'Value',chanval,...
            'HorizontalAlignment','center',...
            'Position',[60+90*(mod((j-1),7)) 40-30*floor((j-1)/7) 80 20],...
            'Callback',{@GetChannel,i,j});
    end

    if numgetchans==0, j=0;
    end

    smaux.smgui.loopvars_getchans_pmh(i,j+1) = uicontrol('Parent',smaux.smgui.loop_panels_ph(i),...
        'Style','popupmenu',...
        'String',["none"; setdiff(channelnames_str, selected_names, "stable")],...
        'Value',1,...
        'HorizontalAlignment','center',...
        'Position',[60+90*(mod(j,7)) 40-30*floor(j/7) 80 20],...
        'Callback',{@GetChannel,i,j+1});
end

function makeconstpanel(varargin)
    global smaux smscan smdata;
    %Set constants panel to below filename panel
    posData = get(smaux.smgui.datapanel,'position');
    height = 150; %was 290
    margin = 10;
    parentsize=[180 posData(2)-height-margin 700 height];
    
    delete(smaux.smgui.scan_constants_ph);
    smaux.smgui.scan_constants_ph = uipanel('Parent',smaux.smgui.nullpanel,'Title','Constants (check to set, uncheck to record)',...
        'Units','Pixels',...
        'Position', parentsize); %'Position', [180 600 700 290]);

    smaux.smgui.update_consts_pbh = uicontrol('Parent',smaux.smgui.scan_constants_ph,...
        'Style','pushbutton',...
        'String','Update Constants',...
        'Position',[560 5 130 25],...
        'Callback',@UpdateConstants);

    numconsts=length(smscan.consts);
    channelnames = getChannelNamesForContext('pure-scalar');  % Use pure scalar names for constants



    
    pos1 = [5 parentsize(4)-40 0 0];
    cols = 4;      
    for i=1:numconsts
        if strcmp('none', smscan.consts(i).setchan)
            chanval=1;
        else
            try
                % Find position in dropdown list, not smdata.channels indices
                chanName = smscan.consts(i).setchan;
                chanval = find(strcmp(channelnames, chanName));
                if isempty(chanval)
                    chanval = 1; % Default to 'none'
                else
                    chanval = chanval + 1; % +1 for 'none' option in popup
                end
            catch ME
                % Build detailed error message for constants
                chanName = smscan.consts(i).setchan;
                if iscell(chanName)
                    chanNameStr = sprintf('{%s}', strjoin(string(chanName), ', '));
                else
                    chanNameStr = string(chanName);
                end
                
                debugMsg = sprintf(['CONSTANTS CHANNEL LOOKUP FAILED\n\n' ...
                                   'Channel: ''%s''\n' ...
                                   'Class: %s\n' ...
                                   'Error: %s\n\n' ...
                                   'Available channels:\n'], ...
                                   chanNameStr, class(chanName), ME.message);
                
                % Add list of available channels
                if exist('smdata', 'var') && isfield(smdata, 'channels') && ~isempty(smdata.channels)
                    for k = 1:min(10, length(smdata.channels))  % Show first 10 channels
                        debugMsg = [debugMsg sprintf('  %d: %s\n', k, smdata.channels(k).name)];
                    end
                    if length(smdata.channels) > 10
                        debugMsg = [debugMsg sprintf('  ... and %d more channels', length(smdata.channels) - 10)];
                    end
                else
                    debugMsg = [debugMsg '  No channels available - check instrument setup'];
                end
                
                errordlg(debugMsg, 'Constants Channel Lookup Error - Detailed Diagnostics');
                chanval=1;
            end
        end
        if isempty(smscan.consts(i).set)
            smscan.consts(i).set=1;
        end
        smaux.smgui.consts_pmh(i) = uicontrol('Parent',smaux.smgui.scan_constants_ph,...
            'Style','popupmenu',...
            'String',['none' channelnames],...
            'Value',chanval,...
            'HorizontalAlignment','center',...
            'Position',pos1+[173*(mod(i-1,cols)) -27*(floor((i-1)/cols)) 96 20],...
            'Callback',{@ConstMenu,i});
        smaux.smgui.consts_eth(i) = uicontrol('Parent',smaux.smgui.scan_constants_ph,...
            'Style','edit',...
            'String',smscan.consts(i).val,...
            'HorizontalAlignment','center',...
            'Position',pos1+[173*(mod(i-1,cols))+98 -27*(floor((i-1)/cols)) 50 20],...
            'Callback',{@ConstTXT,i});
        smaux.smgui.setconsts_cbh(i) = uicontrol('Parent',smaux.smgui.scan_constants_ph,...
            'Style','checkbox',...
            'Position',pos1+[173*(mod(i-1,cols))+150 -27*(floor((i-1)/cols)) 20 20],...
            'Value',smscan.consts(i).set,...
            'Callback',{@SetConsts,i});
    end
    if isempty(i)
        i=0;
    end
    i=i+1;
    chanval = 1;

    smaux.smgui.consts_pmh(i) = uicontrol('Parent',smaux.smgui.scan_constants_ph,...
        'Style','popupmenu',...
        'String',['none' channelnames],...
        'Value',chanval,...
        'HorizontalAlignment','center',...
        'Position',pos1+[173*(mod(i-1,cols)) -27*(floor((i-1)/cols)) 96 20],...
        'Callback',{@ConstMenu,i});

    smaux.smgui.consts_eth(i) = uicontrol('Parent',smaux.smgui.scan_constants_ph,...
        'Style','edit',...
        'String',0,...
        'HorizontalAlignment','center',...
        'Position',pos1+[173*(mod(i-1,cols))+98 -27*(floor((i-1)/cols)) 50 20],...
        'Callback',{@ConstTXT,i});
    smaux.smgui.setconsts_cbh(i) = uicontrol('Parent',smaux.smgui.scan_constants_ph,...
            'Style','checkbox',...
            'Position',pos1+[173*(mod(i-1,cols))+150 -27*(floor((i-1)/cols)) 20 20],...
            'Value',1,...
            'Callback',{@SetConsts,i});

end

%Helper functions for context-aware channel name selection
function names = getVectorChannelNames()
    % Get vector channel names for data acquisition (loopvars_getchans_pmh)
    global bridge;
    
    if ~exist('bridge', 'var') || isempty(bridge) || ~isa(bridge, 'smguiBridge')
        error('smguiBridge is required but not available. Cannot operate without bridge.');
    end
    
    names = bridge.getVectorChannelNames();
end

function names = getScalarChannelNames()
    % Get scalar channel names for plotting and other UI elements
    global bridge;
    
    if ~exist('bridge', 'var') || isempty(bridge) || ~isa(bridge, 'smguiBridge')
        error('smguiBridge is required but not available. Cannot operate without bridge.');
    end
    
    names = bridge.getScalarChannelNames();
end

function names = getPureScalarChannelNames()
    % Get only inherently scalar channel names (excludes expanded vector components)
    % Used for set channel dropdowns
    global bridge;
    
    if ~exist('bridge', 'var') || isempty(bridge) || ~isa(bridge, 'smguiBridge')
        error('smguiBridge is required but not available. Cannot operate without bridge.');
    end
    
    names = bridge.getPureScalarChannelNames();
end

function names = getChannelNamesForContext(context)
    % Get appropriate channel names based on context
    % context: 'vector' for data acquisition, 'scalar' for plotting/UI, 'pure-scalar' for set channels
    if strcmp(context, 'vector')
        names = getVectorChannelNames();
    elseif strcmp(context, 'pure-scalar')
        names = getPureScalarChannelNames();
    else
        names = getScalarChannelNames();
    end
end

function scalarNames = convertVectorToScalarNames(vectorChannelName)
    % Convert a vector channel name to its scalar components
    % e.g., "XY" -> {"XY_1", "XY_2"}
    global bridge;
    
    if ~exist('bridge', 'var') || isempty(bridge) || ~isa(bridge, 'smguiBridge')
        error('smguiBridge is required but not available. Cannot operate without bridge.');
    end
    
    % Convert to string for consistency
    vectorChannelName = char(vectorChannelName);
    
    % Try to get channel size for the vector name
    try
        channelSize = bridge.getChannelSize(vectorChannelName);
    catch
        % Channel not found - return original name as-is
        scalarNames = {vectorChannelName};
        return;
    end
    
    if channelSize == 1
        scalarNames = {vectorChannelName};
    else
        scalarNames = {};
        for i = 1:channelSize
            scalarNames{end+1} = sprintf("%s_%d", vectorChannelName, i);
        end
    end
end


function registerSmallGuiWithPptState()
    global smaux bridge
    smpptEnsureGlobals();
    if ~isstruct(smaux) || ~isfield(smaux, 'smgui') || ~isstruct(smaux.smgui)
        return;
    end
    handles.figure = [];
    if isfield(smaux.smgui, 'figure1')
        handles.figure = smaux.smgui.figure1;
    end
    handles.checkbox = [];
    if isfield(smaux.smgui, 'appendppt_cbh')
        handles.checkbox = smaux.smgui.appendppt_cbh;
    end
    handles.fileLabel = [];
    if isfield(smaux.smgui, 'pptfile_sth')
        handles.fileLabel = smaux.smgui.pptfile_sth;
    end
    smpptRegisterGui('small', handles);
    [currentEnabled, currentFile] = smpptGetState();
    checkboxValue = currentEnabled;
    if ishandle(handles.checkbox)
        checkboxValue = logical(get(handles.checkbox, 'Value'));
    end
    targetEnabled = checkboxValue;
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
        smpptUpdateGlobalState('small', targetEnabled, targetFile);
    end
    smpptApplyStateToGui('small');
end


function registerSmallGuiWithDataState()
    global smaux bridge
    smdatapathEnsureGlobals();
    if ~isstruct(smaux) || ~isfield(smaux, 'smgui') || ~isstruct(smaux.smgui)
        return;
    end

    handles = struct();
    if isfield(smaux.smgui, 'datapath_sth')
        handles.label = smaux.smgui.datapath_sth;
        handles.tooltipHandle = smaux.smgui.datapath_sth;
        handles.displayLimit = 100;
    end
    smdatapathRegisterGui('small', handles);

    currentPath = smdatapathGetState();
    targetPath = currentPath;
    rootPath = string(pwd);
    if exist("bridge", "var") && ~isempty(bridge) && isobject(bridge) && isprop(bridge, "experimentRootPath")
        if strlength(string(bridge.experimentRootPath)) == 0
            bridge.experimentRootPath = pwd;
        end
        rootPath = string(bridge.experimentRootPath);
    end
    if isempty(targetPath)
        if isfield(smaux, 'datadir') && ~isempty(smaux.datadir)
            targetPath = smaux.datadir;
        else
            targetPath = smdatapathDefaultPath();
        end
    else
        smaux.datadir = targetPath;
    end

    if strlength(rootPath) > 0
        if ~startsWith(string(targetPath), rootPath, "IgnoreCase", true)
            [~, relPath] = fileparts(char(targetPath));
            relPath = string(relPath);
            if strlength(relPath) == 0
                relPath = "data";
            end
            targetPath = fullfile(rootPath, relPath);
        end
    end

    if isempty(smaux.datadir) || ~strcmp(char(smaux.datadir), char(targetPath))
        smaux.datadir = targetPath;
    end

    if ~exist(targetPath, 'dir')
        mkdir(targetPath);
    end

    if ~strcmp(char(targetPath), char(currentPath))
        smdatapathUpdateGlobalState('small', targetPath);
    else
        smdatapathApplyStateToGui('small');
    end
end


function registerSmallGuiWithRunState()
    global smaux
    smrunEnsureGlobals();
    if ~isstruct(smaux) || ~isfield(smaux, 'smgui') || ~isstruct(smaux.smgui)
        return;
    end

    handles = struct();
    if isfield(smaux.smgui, 'runnumber_eth')
        handles.edit = smaux.smgui.runnumber_eth;
        handles.tooltipHandle = smaux.smgui.runnumber_eth;
    end
    smrunRegisterGui('small', handles);
end


function sanitized = sanitizeFilename(name)
    % Sanitize a string for use as a Windows filename
    % Replaces invalid characters: \ / : * ? " < > | .
    sanitized = regexprep(name, '[\\/:*?"<>|.]', '_');
end