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
    screenSize = get(0, 'ScreenSize');
    figHeight = min(611, screenSize(4)-80);
    layoutMetrics = smguiLayoutMetrics();
    figWidth = layoutMetrics.bodyX + layoutMetrics.panelW + layoutMetrics.scrollW + 3;
    %  Create and then hide the GUI as it is being constructed.
   smaux.smgui.figure1 = figure('Visible','on',...
       'Name','Special Measure v0.9',...
       'MenuBar','none', ...
       'NumberTitle','off',...
       'IntegerHandle','off',...
       'Position',[0,0,figWidth,figHeight],...
       'Toolbar','none',...
       'Resize','off');
   movegui(smaux.smgui.figure1,'center')

   %put everything in this panel for aesthetic purposes
   smaux.smgui.nullpanel=uipanel('Parent',smaux.smgui.figure1,...
        'Units','pixels','Position',[0,0,figWidth+5,figHeight]);
    
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
        smaux.smgui.ClearScan = uimenu('Parent',smaux.smgui.FileMenu,...
            'Label','Clear Scan',...
            'HandleVisibility','Callback',...
            'Callback',@ClearScan);
        smaux.smgui.EditRack = uimenu('Parent',smaux.smgui.FileMenu,...
            'Separator','on',...
            'Label','Edit Rack',...
            'HandleVisibility','Callback',...
            'Callback',@EditRack);
        setappdata(smaux.smgui.EditRack, "smEditRackBaseLabel", erase(string(get(smaux.smgui.EditRack, "Label")), " (scan active)"));

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
    smaux.smgui.scan_body_view_ph = [];
    smaux.smgui.scan_body_content_ph = [];
    smaux.smgui.scan_body_scroll_slh = [];
    smaux.smgui.scan_body_scroll = 0;
    

    
    
    leftX = 3;
    leftW = 254;
    leftPad = 5;
    rowTextYOffset = layoutMetrics.textYOffset;
    topPad = 6;
    scanH = smguiLeftPanelHeight(1, layoutMetrics);

    panYscan = figHeight - topPad - scanH;
    smaux.smgui.scantitle_panel = uipanel('Parent',smaux.smgui.nullpanel,'Title','Scan Name',...
        'Units','pixels',...
        'Position',[leftX panYscan leftW scanH]);
        smaux.smgui.scantitle_eth = uicontrol('Parent',smaux.smgui.scantitle_panel,'Style','edit',...
            'String','',...
            'HorizontalAlignment','left',...
            'FontSize',8,...
            'Position',[4 smguiLeftPanelRowY(scanH, 1, layoutMetrics) leftW-8 layoutMetrics.ctrlH],...
            'Callback',@ScanTitle);

    fixedInfoH = smguiFixedInfoHeight(layoutMetrics);
    fixedInfoY = figHeight - topPad - fixedInfoH;
    fixedInfoGap = 8;
    dataW = 270;
    pptW = 175;
    commentW = layoutMetrics.panelW - dataW - pptW - 2 * fixedInfoGap;
    fixedInfoX = layoutMetrics.bodyX;
    smaux.smgui.datapanel = uipanel('Parent',smaux.smgui.nullpanel,'Title','Data File',...
        'Units','pixels',...
        'Position',[fixedInfoX fixedInfoY dataW fixedInfoH]);
        smaux.smgui.savedata_pbh = uicontrol('Parent',smaux.smgui.datapanel,'Style','pushbutton',...
            'String','Path',...
            'Position',[4 smguiLeftPanelRowY(fixedInfoH, 1, layoutMetrics) 50 layoutMetrics.ctrlH],...
            'Callback',@SavePath);
        smaux.smgui.datapath_sth = uicontrol('Parent',smaux.smgui.datapanel,'Style','text',...
            'String','',...
            'HorizontalAlignment','left',...
            'FontSize',8,...
            'Max',50,...
            'Position',[58 smguiLeftPanelRowY(fixedInfoH, 1, layoutMetrics)+rowTextYOffset dataW-64 layoutMetrics.ctrlH]);
        smaux.smgui.filename_pbh = uicontrol('Parent',smaux.smgui.datapanel,'Style','pushbutton',...
            'String','File',...
            'HorizontalAlignment','center',...
            'FontSize',8,...
            'ToolTipString','Full file name = path\filename_run.mat',...
            'Position',[4 smguiLeftPanelRowY(fixedInfoH, 2, layoutMetrics) 50 layoutMetrics.ctrlH],...
            'Callback',@FileName);
        smaux.smgui.filename_eth = uicontrol('Parent',smaux.smgui.datapanel,'Style','edit',...
            'String','',...
            'HorizontalAlignment','left',...
            'FontSize',8,...
            'Position',[58 smguiLeftPanelRowY(fixedInfoH, 2, layoutMetrics) dataW-64 layoutMetrics.ctrlH]);
        smaux.smgui.runnumber_sth = uicontrol('Parent',smaux.smgui.datapanel,'Style','text',...
            'String','Run:',...
            'HorizontalAlignment','right',...
            'FontSize',8,...
            'Position',[4 smguiLeftPanelRowY(fixedInfoH, 3, layoutMetrics)+rowTextYOffset 30 layoutMetrics.ctrlH]);
        smaux.smgui.runnumber_eth = uicontrol('Parent',smaux.smgui.datapanel,'Style','edit',...
            'String','',...
            'HorizontalAlignment','left',...
            'FontSize',8,...
            'Position',[38 smguiLeftPanelRowY(fixedInfoH, 3, layoutMetrics) 35 layoutMetrics.ctrlH],...
            'Callback',@RunNumber);
        if ~isfield(smaux, "run")
            smaux.run = [];
        end
        smaux.smgui.autoincrement_cbh = uicontrol('Parent',smaux.smgui.datapanel,'Style','checkbox',...
            'String','AutoIncrement',...
            'HorizontalAlignment','left',...
            'FontSize',7,...
            'ToolTipString','Selecting this will automatically increase run after hitting measure',...
            'Position',[80 smguiLeftPanelRowY(fixedInfoH, 3, layoutMetrics) dataW-86 layoutMetrics.ctrlH],...
            'Value',1);

    smaux.smgui.pptpanel = uipanel('Parent',smaux.smgui.nullpanel,'Title','PowerPoint Log',...
        'Units','pixels',...
        'Position',[fixedInfoX + dataW + fixedInfoGap fixedInfoY pptW fixedInfoH]);
        smaux.smgui.saveppt_pbh = uicontrol('Parent',smaux.smgui.pptpanel,'Style','pushbutton',...
            'String','File',...
            'Position',[4 smguiLeftPanelRowY(fixedInfoH, 1, layoutMetrics) 60 layoutMetrics.ctrlH],...
            'FontSize',8,...
            'Callback',@SavePPT);
        smaux.smgui.pptfile_sth = uicontrol('Parent',smaux.smgui.pptpanel,'Style','text',...
            'String','',...
            'HorizontalAlignment','center',...
            'FontSize',7,...
            'Position',[2 smguiLeftPanelRowY(fixedInfoH, 2, layoutMetrics)+rowTextYOffset pptW-6 layoutMetrics.ctrlH]);
        smaux.smgui.appendppt_cbh = uicontrol('Parent',smaux.smgui.pptpanel,'Style','checkbox',...
            'String','Log',...
            'Position',[pptW-78 smguiLeftPanelRowY(fixedInfoH, 1, layoutMetrics) 70 layoutMetrics.ctrlH],...
            'HorizontalAlignment','left',...
            'FontSize',8,...
            'Value',1,...
            'Callback',@AppendPptToggle);

    smaux.smgui.commenttext_sth = uipanel('Parent',smaux.smgui.nullpanel,'Title','Comments',...
        'Units','pixels',...
        'Position',[fixedInfoX + dataW + pptW + 2 * fixedInfoGap fixedInfoY commentW fixedInfoH]);
    smaux.smgui.commenttext_eth = uicontrol('Parent',smaux.smgui.commenttext_sth,'Style','edit',...
        'String','',...
        'FontSize',8,...
        'Position',[4 layoutMetrics.ctrlPadY commentW-8 fixedInfoH-layoutMetrics.titlePad-2*layoutMetrics.ctrlPadY],...
        'HorizontalAlignment','left',...
        'max',20,...
        'Callback',@Comment);
        
    
    panYloops = panYscan - 35;
    smaux.smgui.numloops_sth = uicontrol('Parent',smaux.smgui.nullpanel,'Style','text',...
        'String','Loops:',...
        'HorizontalAlignment','right',...
        'Position',[leftPad panYloops+rowTextYOffset 40 20]);
    smaux.smgui.numloops_eth = uicontrol('Parent',smaux.smgui.nullpanel,'Style','edit',...
        'String','1',...
        'Position',[48 panYloops 20 20],...
        'TooltipString','Number of loops',...
        'Callback',@NumLoops);
    
    smaux.smgui.saveloop_sth = uicontrol('Parent',smaux.smgui.nullpanel,'Style','text',...
        'String','Save Loop:',...
        'HorizontalAlignment','left',...
        'Position',[86 panYloops+rowTextYOffset 70 20]);
    smaux.smgui.saveloop_eth = uicontrol('Parent',smaux.smgui.nullpanel,'Style','edit',...
        'String','1',...
        'Position',[155 panYloops 20 20],...
        'TooltipString','Data is saved during this loop. Setting to 1 will save at each point',...
        'Callback',@SaveLoop);
    panYDisp = panYloops - 35;
    %UI Controls for plot selection
    smaux.smgui.oneDplot_sth = uicontrol('Parent',smaux.smgui.nullpanel,'Style','text',...
        'String','1D Plots',...
        'Position',[leftX panYDisp 95 20]);
    plotListHeight = 21 * 16;
    plotGap = 14;
    plotW = floor((leftW - plotGap) / 2);
    plotX2 = leftX + plotW + plotGap;
    smaux.smgui.oneDplot_lbh = uicontrol('Parent',smaux.smgui.nullpanel,'Style','listbox',...
        'String',{},...
        'Max',10,...
        'Position',[leftX panYDisp-plotListHeight plotW plotListHeight],...
        'Callback',@Plot);
    smaux.smgui.twoDplot_sth = uicontrol('Parent',smaux.smgui.nullpanel,'Style','text',...
        'String','2D Plots',...
        'Position',[plotX2 panYDisp plotW 20]);
    smaux.smgui.twoDplot_lbh = uicontrol('Parent',smaux.smgui.nullpanel,'Style','listbox',...
        'String',{},...
        'Max',10,...
        'Position',[plotX2 panYDisp-plotListHeight plotW plotListHeight],...
        'Callback',@Plot);
    
    panYbuttons = panYDisp - plotListHeight - 55;
    buttonH = 30;
    buttonGap = buttonH / 2;
    %UI Controls to add smscan to collection of scans or measurement queue
    smaux.smgui.toscans_pbh = uicontrol('Parent',smaux.smgui.nullpanel,'Style','pushbutton',...
        'String','TO SCANS',...
        'FontSize',14,...
        'Position', [leftX panYbuttons leftW buttonH],...
        'Callback',@ToScans);
        
    smaux.smgui.toqueue_pbh = uicontrol('Parent',smaux.smgui.nullpanel,'Style','pushbutton',...
        'String','TO QUEUE',...
        'FontSize',14,...
        'Position', [leftX panYbuttons-buttonH-buttonGap leftW buttonH],...
        'Callback',@ToQueue);
    
    smaux.smgui.smrun_pbh = uicontrol('Parent',smaux.smgui.nullpanel,'Style','pushbutton',...
        'String','RUN',...
        'FontSize',14,...
        'Position',[leftX panYbuttons-2*(buttonH+buttonGap) leftW buttonH],...
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

function ClearScan(hObject,eventdata)
    global smscan
    smscan = struct();
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
    smscan.saveloop = 2;
    smscan.disp = [];
    smscan.comments = '';
    smscan.name = '';
    scaninit;
end

function EditRack(hObject,eventdata)
    smeditrack();
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
    makescanbody;
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
    makescanbody;
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
            makescanbody;
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
    end
    makescanbody;
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
    end
    makescanbody;
end

%Callback for getchannel pmh
function GetChannel(hObject,eventdata,i,j)
global smaux smscan smdata bridge;
    val = get(smaux.smgui.loopvars_getchans_pmh(i,j),'Value');
    if val==1
        if j <= length(smscan.loops(i).getchan)
            smscan.loops(i).getchan(j)=[];
        end
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
                if j <= length(smscan.loops(i).getchan)
                    smscan.loops(i).getchan(j) = [];
                end
            else
                % Store the vector channel name - setplotchoices will handle expansion
                smscan.loops(i).getchan{j} = selectedVectorChannel;
            end
        else
            if j <= length(smscan.loops(i).getchan)
                smscan.loops(i).getchan(j) = [];
            end
        end
    end
    makescanbody;
end

%Callback for the constants pmh
function ConstMenu(hObject,eventdata,i)
global smaux smscan smdata bridge;
    val=get(smaux.smgui.consts_pmh(i),'Value');
    popupStrings = get(smaux.smgui.consts_pmh(i), "String");
    if iscell(popupStrings)
        popupStrings = string(popupStrings);
    elseif ischar(popupStrings)
        popupStrings = string(popupStrings);
    end
    if val==1
        if i <= length(smscan.consts)
            smscan.consts(i)=[];
        end
    elseif val <= numel(popupStrings)
        selectedScalarChannel = popupStrings(val);
        if selectedScalarChannel == "none"
            if i <= length(smscan.consts)
                smscan.consts(i)=[];
            end
            makescanbody;
            return;
        end
        smscan.consts(i).setchan = selectedScalarChannel;
        if ~isfield(smscan.consts(i),'val') || isempty(smscan.consts(i).val)
            smscan.consts(i).val=0;
        end
        if ~isfield(smscan.consts(i),'set') || isempty(smscan.consts(i).set)
            smscan.consts(i).set=1;
        end
    else
        if i <= length(smscan.consts)
            smscan.consts(i)=[];
        end
    end
    makescanbody;
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
       
    makescanbody;
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
       
    makescanbody;
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
        
        % Disable 2D plots selection when there is only 1 loop
        numloops = length(smscan.loops);
        twoDEnabled = numloops > 1;
        if ~twoDEnabled && isfield(smscan, 'disp') && ~isempty(smscan.disp)
            keepMask = true(1, numel(smscan.disp));
            for k = 1:numel(smscan.disp)
                keepMask(k) = ~isfield(smscan.disp(k), 'dim') || ~isequal(smscan.disp(k).dim, 2);
            end
            smscan.disp = smscan.disp(keepMask);
        end
        set(smaux.smgui.twoDplot_sth, 'Enable', onOffState(twoDEnabled));
        
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
                newoneDvals = [newoneDvals channel_idx]; %#ok<AGROW>
            elseif smscan.disp(i).dim == 2
                mapped_idx = full_to_2d(channel_idx);
                if mapped_idx > 0
                    newtwoDvals = [newtwoDvals mapped_idx]; %#ok<AGROW>
                else
                    valid_disp_mask(i) = false;
                end
            end
        end
        if any(~valid_disp_mask)
            smscan.disp = smscan.disp(valid_disp_mask);
        end
        newoneDvals = unique(sort(newoneDvals));
        newtwoDvals = unique(sort(newtwoDvals));
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
        dispEntries = struct('loop', {}, 'channel', {}, 'dim', {}, 'name', {});
        entryIndex = 0;
        for i = 1:length(newoneDvals)
            chanIdx = newoneDvals(i);
            entryIndex = entryIndex + 1;
            dispEntries(entryIndex).loop = plotchoicesAll.loop(chanIdx);
            dispEntries(entryIndex).channel = chanIdx;
            dispEntries(entryIndex).dim = 1;
            dispEntries(entryIndex).name = string(plotchoicesAll.string{chanIdx});
        end
        for i = 1:length(newtwoDvals)
            local_idx = newtwoDvals(i);
            entryIndex = entryIndex + 1;
            dispEntries(entryIndex).loop = plotchoices2d.loop(local_idx) + 1;
            dispEntries(entryIndex).channel = plotchoices2d.full_index(local_idx);
            dispEntries(entryIndex).dim = 2;
            dispEntries(entryIndex).name = string(plotchoices2d.string{local_idx});
        end
        smscan.disp = dispEntries;
        refreshPlotListbox(smaux.smgui.oneDplot_lbh, plotchoicesAll.string, newoneDvals, true);
        refreshPlotListbox(smaux.smgui.twoDplot_lbh, plotchoices2d.string, newtwoDvals, twoDEnabled);
end

function refreshPlotListbox(handle, items, values, enabled)
    itemCount = numel(items);
    set(handle, 'Value', 1, 'ListboxTop', 1);
    if itemCount == 0
        set(handle, 'String', {''}, 'Value', 1, 'ListboxTop', 1);
    else
        values = values(values >= 1 & values <= itemCount);
        set(handle, 'String', items, 'Value', values, 'ListboxTop', 1);
    end
    set(handle, 'Enable', onOffState(enabled));
end

function state = onOffState(enabled)
    if enabled
        state = 'on';
    else
        state = 'off';
    end
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

    smbridgeAddSharedPaths();
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

    smbridgeUpdateEditRackMenuState(true);
    cleanupEditRackMenu = onCleanup(@() smbridgeUpdateEditRackMenuState(false));
    drawnow;
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
    smbridgeUpdateEditRackMenuState();
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
        makescanbody;
        setplotchoices;
        
end

function makelooppanels(varargin)
    makescanbody;
end

function makeconstpanel(varargin)
    makescanbody;
end

function makescanbody(varargin)
    global smaux smscan;
    m = smguiLayoutMetrics();
    numloops = length(smscan.loops);
    if numloops < 1
        return;
    end

    outerScroll = getStoredScroll("scan_body_scroll", "scan_body_scroll_slh", 0);
    constScroll = getStoredScroll("const_scroll", "const_scroll_slh", 0);
    loopScrolls = zeros(1, numloops);
    if isfield(smaux.smgui, "loop_scroll")
        old = smaux.smgui.loop_scroll;
        loopScrolls(1:min(numloops, numel(old))) = old(1:min(numloops, numel(old)));
    end

    deleteIfGraphic("scan_body_view_ph");
    deleteIfGraphic("scan_body_scroll_slh");
    smaux.smgui.consts_pmh = [];
    smaux.smgui.consts_eth = [];
    smaux.smgui.setconsts_cbh = [];
    smaux.smgui.loop_panels_ph = [];
    smaux.smgui.loop_content_ph = [];
    smaux.smgui.loop_content_scroll_slh = [];
    smaux.smgui.loopvars_eth = [];
    smaux.smgui.loopvars_sth = [];
    smaux.smgui.loopvars_getchans_pmh = [];
    smaux.smgui.loopcvars_sth = [];
    smaux.smgui.loopcvars_eth = [];
    smaux.smgui.loopcvars_delchan_pbh = [];

    constRows = max(1, ceil((length(smscan.consts) + 1) / m.constCols));
    constVisibleRows = min(m.maxContentRows, constRows);
    constHeight = m.titlePad + m.rowH * (constVisibleRows + 1) + m.bottomPad;

    smscan.loops = normalizeLoopFields(smscan.loops);
    loopHeights = zeros(1, numloops);
    loopSetRows = zeros(1, numloops);
    loopRecordRows = zeros(1, numloops);
    loopContentRows = zeros(1, numloops);
    for i = 1:numloops
        smscan.loops(i).numchans = length(smscan.loops(i).setchan);
        loopSetRows(i) = max(1, smscan.loops(i).numchans);
        loopRecordRows(i) = max(1, ceil((length(smscan.loops(i).getchan) + 1) / m.recordCols));
        loopContentRows(i) = loopSetRows(i) + loopRecordRows(i);
        visibleRows = min(m.maxContentRows, loopContentRows(i));
        loopHeights(i) = m.titlePad + m.rowH * (1 + visibleRows) + m.bottomPad;
    end

    contentHeight = constHeight + m.margin + sum(loopHeights) + m.margin * max(0, numloops - 1);
    bodyBottom = 5;
    posNull = get(smaux.smgui.nullpanel, "Position");
    bodyHeight = max(100, posNull(4) - m.topPad - smguiFixedInfoHeight(m) - m.margin - bodyBottom);
    smaux.smgui.scan_body_view_ph = uipanel("Parent", smaux.smgui.nullpanel, ...
        "Units", "pixels", "BorderType", "none", ...
        "Position", [m.bodyX bodyBottom m.panelW bodyHeight]);
    [smaux.smgui.scan_body_content_ph, smaux.smgui.scan_body_scroll_slh, outerScroll] = ...
        createScrollContent(smaux.smgui.nullpanel, smaux.smgui.scan_body_view_ph, ...
        [m.bodyX + m.panelW + 1 bodyBottom m.scrollW bodyHeight], ...
        m.panelW, bodyHeight, contentHeight, outerScroll, "body", 0);
    smaux.smgui.scan_body_scroll = outerScroll;

    y = contentHeight - constHeight;
    makeConstantsPanel(smaux.smgui.scan_body_content_ph, [0 y m.panelW constHeight], constRows, constScroll);
    y = y - m.margin;

    for i = 1:numloops
        y = y - loopHeights(i);
        makeLoopPanel(smaux.smgui.scan_body_content_ph, [0 y m.panelW loopHeights(i)], i, ...
            loopSetRows(i), loopRecordRows(i), loopContentRows(i), loopScrolls(i));
        y = y - m.margin;
    end

    set(smaux.smgui.loop_panels_ph(numloops), "Title", sprintf("Loop %d (outer)", numloops));
    set(smaux.smgui.loop_panels_ph(1), "Title", sprintf("Loop %d (inner)", 1));
    for k = 2:numloops-1
        set(smaux.smgui.loop_panels_ph(k), "Title", sprintf("Loop %d", k));
    end
    setplotchoices;
end

function makeConstantsPanel(parent, panelPos, constRows, constScroll)
    global smaux smscan;
    m = smguiLayoutMetrics();
    visibleRows = min(m.maxContentRows, constRows);
    smaux.smgui.scan_constants_ph = uipanel("Parent", parent, "Title", "Constants (check to set, uncheck to record)", ...
        "Units", "pixels", "Position", panelPos);
    smaux.smgui.update_consts_pbh = uicontrol("Parent", smaux.smgui.scan_constants_ph, ...
        "Style", "pushbutton", ...
        "String", "Update Constants", ...
        "Position", [m.panelW - 140 m.bottomPad + m.ctrlPadY 130 m.ctrlH], ...
        "Callback", @UpdateConstants);

    rowViewY = m.bottomPad + m.rowH;
    rowViewH = visibleRows * m.rowH;
    [rowContent, smaux.smgui.const_scroll_slh, constScroll] = createScrollContent( ...
        smaux.smgui.scan_constants_ph, smaux.smgui.scan_constants_ph, ...
        [m.internalSliderX rowViewY m.scrollW rowViewH], ...
        m.rowViewW, rowViewH, constRows * m.rowH, constScroll, "const", 0, [5 rowViewY m.rowViewW rowViewH]);
    smaux.smgui.const_scroll = constScroll;

    channelnames = getChannelNamesForContext("pure-scalar");
    for i = 1:length(smscan.consts)
        chanval = find(strcmp(channelnames, smscan.consts(i).setchan));
        if isempty(chanval)
            chanval = 1;
        else
            chanval = chanval + 1;
        end
        if isempty(smscan.consts(i).set)
            smscan.consts(i).set = 1;
        end
        makeConstControls(rowContent, i, chanval, smscan.consts(i).val, smscan.consts(i).set, constRows, channelnames);
    end
    makeConstControls(rowContent, length(smscan.consts) + 1, 1, 0, 1, constRows, channelnames);
end

function makeConstControls(parent, i, chanval, constVal, setVal, constRows, channelnames)
    global smaux smscan;
    m = smguiLayoutMetrics();
    channelnames = string(channelnames(:));
    currentName = "";
    if chanval > 1 && chanval - 1 <= numel(channelnames)
        currentName = channelnames(chanval - 1);
    end
    selectedNames = string.empty(0, 1);
    for constIdx = 1:length(smscan.consts)
        if constIdx == i || ~isfield(smscan.consts, "setchan") || isempty(smscan.consts(constIdx).setchan)
            continue;
        end
        selectedName = string(smscan.consts(constIdx).setchan);
        if strlength(selectedName) > 0 && selectedName ~= "none"
            selectedNames(end+1, 1) = selectedName; %#ok<AGROW>
        end
    end
    availableNames = setdiff(channelnames, selectedNames, "stable");
    if strlength(currentName) > 0 && ~any(availableNames == currentName)
        availableNames = [currentName; availableNames];
    end
    chanval = 1;
    if strlength(currentName) > 0
        matchIdx = find(availableNames == currentName, 1);
        if ~isempty(matchIdx)
            chanval = matchIdx + 1;
        end
    end
    row = floor((i-1) / m.constCols) + 1;
    col = mod(i-1, m.constCols);
    y = constRows * m.rowH - row * m.rowH + m.ctrlPadY;
    colW = m.rowViewW / m.constCols;
    x = colW * col;
    smaux.smgui.consts_pmh(i) = uicontrol("Parent", parent, ...
        "Style", "popupmenu", ...
        "String", ["none"; availableNames], ...
        "Value", chanval, ...
        "HorizontalAlignment", "center", ...
        "Position", [x y m.constPopupW m.ctrlH], ...
        "Callback", {@ConstMenu,i});
    smaux.smgui.consts_eth(i) = uicontrol("Parent", parent, ...
        "Style", "edit", ...
        "String", constVal, ...
        "HorizontalAlignment", "center", ...
        "Position", [x + m.constPopupW + m.inlineGap y m.constEditW m.ctrlH], ...
        "Callback", {@ConstTXT,i});
    smaux.smgui.setconsts_cbh(i) = uicontrol("Parent", parent, ...
        "Style", "checkbox", ...
        "Position", [x + m.constPopupW + m.constEditW + 2*m.inlineGap y m.constCheckW m.ctrlH], ...
        "Value", setVal, ...
        "Callback", {@SetConsts,i});
end

function makeLoopPanel(parent, panelPos, i, setRows, recordRows, contentRows, scrollValue)
    global smaux smscan;
    m = smguiLayoutMetrics();
    visibleRows = min(m.maxContentRows, contentRows);
    smaux.smgui.loop_panels_ph(i) = uipanel("Parent", parent, ...
        "Units", "pixels", "Position", panelPos);

    headerY = panelPos(4) - m.titlePad - m.rowH + m.ctrlPadY;
    header = smguiLoopHeaderLayout(m, headerY);
    smaux.smgui.loopvars_addchan_pbh(i) = uicontrol("Parent", smaux.smgui.loop_panels_ph(i), ...
        "Style", "pushbutton", ...
        "String", "Add Channel", ...
        "Position", header.add, ...
        "Callback", {@loopvars_addchan_pbh_Callback,i});

    if isfield(smscan.loops(i), "npoints")
        numpoints = smscan.loops(i).npoints;
    else
        numpoints = nan;
    end
    makeLoopHeaderEdit(i, 1, "Points:", header.label(1,:), header.edit(1,:), numpoints, "");
    makeLoopHeaderEdit(i, 4, "Start Wait:", header.label(2,:), header.edit(2,:), loopValueOrZero(smscan.loops(i), "startwait"), "After setting first value of loop, waits this amount of time (s)");
    makeLoopHeaderEdit(i, 2, "Step time:", header.label(3,:), header.edit(3,:), loopValueOrZero(smscan.loops(i), "ramptime"), "(s) Time when ramping between each point");
    makeLoopHeaderEdit(i, 3, "Wait (s):", header.label(4,:), header.edit(4,:), loopValueOrZero(smscan.loops(i), "waittime"), "(s) Wait before getting data");

    rowViewY = m.bottomPad;
    rowViewH = visibleRows * m.rowH;
    contentHeight = contentRows * m.rowH;
    [smaux.smgui.loop_content_ph(i), loopSlider, scrollValue] = createScrollContent( ...
        smaux.smgui.loop_panels_ph(i), smaux.smgui.loop_panels_ph(i), ...
        [m.internalSliderX rowViewY m.scrollW rowViewH], ...
        m.rowViewW, rowViewH, contentHeight, scrollValue, "loop", i, [5 rowViewY m.rowViewW rowViewH]);
    if isempty(loopSlider)
        loopSlider = gobjects(1);
    end
    smaux.smgui.loop_content_scroll_slh(i) = loopSlider;
    smaux.smgui.loop_scroll(i) = scrollValue;

    for j = 1:smscan.loops(i).numchans
        makeloopchannelset(i,j);
    end
    recordStartY = contentHeight - m.rowH * (setRows + 1) + m.ctrlPadY;
    smaux.smgui.looprecord_sth(i) = uicontrol("Parent", smaux.smgui.loop_content_ph(i), ...
        "Style", "text", ...
        "String", "Record:", ...
        "HorizontalAlignment", "center", ...
        "Position", [5 recordStartY + m.textYOffset 50 m.ctrlH]);
    makeloopgetchans(i, recordStartY);
end

function makeLoopHeaderEdit(loopIdx, fieldIdx, label, labelPos, editPos, value, tooltip)
    global smaux;
    smaux.smgui.loopvars_sth(loopIdx,fieldIdx) = uicontrol("Parent", smaux.smgui.loop_panels_ph(loopIdx), ...
        "Style", "text", ...
        "String", label, ...
        "HorizontalAlignment", "right", ...
        "Position", labelPos);
    smaux.smgui.loopvars_eth(loopIdx,fieldIdx) = uicontrol("Parent", smaux.smgui.loop_panels_ph(loopIdx), ...
        "Style", "edit", ...
        "String", value, ...
        "ToolTipString", tooltip, ...
        "HorizontalAlignment", "center", ...
        "Position", editPos, ...
        "Callback", {@loopvars_eth_Callback,loopIdx,fieldIdx});
end

function header = smguiLoopHeaderLayout(m, y)
    labelW = [50 70 65 55];
    editW = [50 35 55 55];
    rowRight = m.panelW - 20;
    x = rowRight - sum(labelW) - sum(editW) - m.headerGap * (numel(labelW)-1);
    header.add = [25 y 100 m.ctrlH];
    header.label = zeros(numel(labelW), 4);
    header.edit = zeros(numel(editW), 4);
    for k = 1:numel(labelW)
        header.label(k,:) = [x y + m.textYOffset labelW(k) m.ctrlH];
        x = x + labelW(k);
        header.edit(k,:) = [x y editW(k) m.ctrlH];
        x = x + editW(k) + m.headerGap;
    end
end

function height = smguiLeftPanelHeight(numRows, m)
    height = m.titlePad + numRows * m.rowH + 2 * m.ctrlPadY;
end

function height = smguiFixedInfoHeight(m)
    height = smguiLeftPanelHeight(3, m);
end

function y = smguiLeftPanelRowY(panelHeight, row, m)
    y = panelHeight - m.titlePad - row * m.rowH + m.ctrlPadY;
end

function m = smguiLayoutMetrics()
    m.bodyX = 267;
    m.panelW = 794;
    m.rowViewW = 774;
    m.internalSliderX = 778;
    m.scrollW = 12;
    m.margin = 10;
    m.topPad = 6;
    m.inlineGap = 3;
    m.headerGap = 12;
    m.rowH = 24;
    m.ctrlH = 20;
    m.ctrlPadY = 2;
    m.textYOffset = -2;
    m.titlePad = 20;
    m.bottomPad = 8;
    m.maxContentRows = 5;
    m.constCols = 4;
    m.constPopupW = 120;
    m.constEditW = 44;
    m.constCheckW = 16;
    m.recordCols = 6;
    m.recordX = 60;
    m.recordW = 110;
    m.recordGap = 6;
end

function loops = normalizeLoopFields(loops)
    for i = 1:numel(loops)
        if ~isfield(loops, "npoints") || isempty(loops(i).npoints), loops(i).npoints = 101; end
        if ~isfield(loops, "rng") || isempty(loops(i).rng), loops(i).rng = [0 1]; end
        if ~isfield(loops, "getchan") || isempty(loops(i).getchan), loops(i).getchan = cell(1,0); end
        if ~isfield(loops, "setchan") || isempty(loops(i).setchan), loops(i).setchan = cell(1,0); end
        if ~isfield(loops, "setchanranges") || isempty(loops(i).setchanranges), loops(i).setchanranges = cell(1,0); end
        if ~isfield(loops, "ramptime") || isempty(loops(i).ramptime), loops(i).ramptime = 0; end
        if ~isfield(loops, "waittime") || isempty(loops(i).waittime), loops(i).waittime = 0; end
        if ~isfield(loops, "startwait") || isempty(loops(i).startwait), loops(i).startwait = 0; end
        loops(i).numchans = length(loops(i).setchan);
    end
end

function value = loopValueOrZero(loop, fieldName)
    if isfield(loop, fieldName) && ~isempty(loop.(fieldName))
        value = loop.(fieldName);
    else
        value = 0;
    end
end

function [content, slider, scrollValue] = createScrollContent(sliderParent, viewParent, sliderPos, contentW, viewH, contentH, scrollValue, kind, idx, viewPos)
    if nargin < 10
        viewPos = get(viewParent, "Position");
        viewPos = [0 0 viewPos(3) viewPos(4)];
    end
    view = uipanel("Parent", viewParent, "Units", "pixels", "BorderType", "none", "Position", viewPos);
    maxScroll = max(0, contentH - viewH);
    scrollValue = min(max(scrollValue, 0), maxScroll);
    contentY = viewH - contentH + scrollValue;
    content = uipanel("Parent", view, "Units", "pixels", "BorderType", "none", ...
        "Position", [0 contentY contentW contentH]);
    slider = [];
    if maxScroll > 0
        slider = uicontrol("Parent", sliderParent, ...
            "Style", "slider", ...
            "Min", 0, ...
            "Max", maxScroll, ...
            "Value", maxScroll - scrollValue, ...
            "SliderStep", [min(1, 24 / maxScroll) min(1, 120 / maxScroll)], ...
            "Position", sliderPos, ...
            "Callback", {@ScrollContent, content, viewH, contentH, kind, idx});
    end
end

function ScrollContent(slider, ~, content, viewH, contentH, kind, idx)
    global smaux;
    maxScroll = max(0, contentH - viewH);
    scrollValue = maxScroll - get(slider, "Value");
    scrollValue = min(max(scrollValue, 0), maxScroll);
    pos = get(content, "Position");
    pos(2) = viewH - contentH + scrollValue;
    set(content, "Position", pos);
    if kind == "body"
        smaux.smgui.scan_body_scroll = scrollValue;
    elseif kind == "const"
        smaux.smgui.const_scroll = scrollValue;
    elseif kind == "loop"
        smaux.smgui.loop_scroll(idx) = scrollValue;
    end
end

function value = getStoredScroll(valueField, handleField, fallback)
    global smaux;
    value = fallback;
    if isfield(smaux.smgui, valueField)
        value = smaux.smgui.(valueField);
    end
    if isfield(smaux.smgui, handleField) && ~isempty(smaux.smgui.(handleField)) && isgraphics(smaux.smgui.(handleField))
        slider = smaux.smgui.(handleField);
        value = get(slider, "Max") - get(slider, "Value");
    end
end

function deleteIfGraphic(fieldName)
    global smaux;
    if isfield(smaux.smgui, fieldName) && ~isempty(smaux.smgui.(fieldName)) && isgraphics(smaux.smgui.(fieldName))
        delete(smaux.smgui.(fieldName));
    end
end

function row = smguiSetRowLayout(m, y)
    labelW = [32 32 32 44 34];
    editW = 40 * ones(1, numel(labelW));
    row.delete = [5 y 50 m.ctrlH];
    row.channelLabel = [58 y + m.textYOffset 45 m.ctrlH];
    row.channelPopup = [row.channelLabel(1) + row.channelLabel(3) + m.inlineGap y 90 m.ctrlH];
    x = row.channelPopup(1) + row.channelPopup(3) + 7;
    totalW = sum(labelW) + sum(editW) + m.inlineGap*numel(labelW);
    paramGap = max(6, (m.rowViewW - x - totalW) / (numel(labelW)-1));
    row.paramLabel = zeros(numel(labelW), 4);
    row.paramEdit = zeros(numel(labelW), 4);
    for k = 1:numel(labelW)
        row.paramLabel(k,:) = [x y + m.textYOffset labelW(k) m.ctrlH];
        x = x + labelW(k) + m.inlineGap;
        row.paramEdit(k,:) = [x y editW(k) m.ctrlH];
        x = x + editW(k) + paramGap;
    end
end

% makes ui objects for setchannel j on loop i                
function makeloopchannelset(i,j) 
    global smaux smscan smdata;
    m = smguiLayoutMetrics();
    parent = smaux.smgui.loop_content_ph(i);
    size = get(parent,'Position');
    row = smguiSetRowLayout(m, size(4)-m.rowH*j+m.ctrlPadY);

    % button to delete this setchannel
    smaux.smgui.loopcvars_delchan_pbh(i,j) = uicontrol('Parent',parent,...
        'Style','pushbutton',...
        'String','Delete',...
        'Position',row.delete,...
        'Callback',{@loopcvars_delchan_pbh_Callback,i,j});

    % select channel being ramped
    channelnames = getChannelNamesForContext('pure-scalar');  % Use pure scalar names for set channels
    smaux.smgui.loopcvars_sth(i,j,1) = uicontrol('Parent',parent,...
        'Style','text',...
        'String','Channel:',...
        'HorizontalAlignment','right',...
        'Position',row.channelLabel);

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
                    debugMsg = [debugMsg sprintf('  %d: %s\n', k, smdata.channels(k).name)]; %#ok<AGROW>
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
    smaux.smgui.loopcvars_eth(i,j,1) = uicontrol('Parent',parent,...
        'Style','popupmenu',...
        'String',['none' channelnames],...
        'Value',chanval,...
        'HorizontalAlignment','center',...
        'Position',row.channelPopup,...
        'Callback',{@loopcvars_eth_Callback,i,j,1});

    if isfield(smscan.loops(i), 'setchanranges')
        if iscell(smscan.loops(i).setchanranges)
            %minimum
            smaux.smgui.loopcvars_sth(i,j,2) = uicontrol('Parent',parent,...
                'Style','text',...
                'String','Min:',...
                'HorizontalAlignment','right');
            smaux.smgui.loopcvars_eth(i,j,2) = uicontrol('Parent',parent,...
                'Style','edit',...
                'String',smscan.loops(i).setchanranges{j}(1),...
                'HorizontalAlignment','center',...
                'Callback',{@loopcvars_eth_Callback,i,j,2});

            %max
            smaux.smgui.loopcvars_sth(i,j,3) = uicontrol('Parent',parent,...
                'Style','text',...
                'String','Max:',...
                'HorizontalAlignment','right');
            smaux.smgui.loopcvars_eth(i,j,3) = uicontrol('Parent',parent,...
                'Style','edit',...
                'String',smscan.loops(i).setchanranges{j}(2),...
                'HorizontalAlignment','center',...
                'Callback',{@loopcvars_eth_Callback,i,j,3});

            %mid
            smaux.smgui.loopcvars_sth(i,j,4) = uicontrol('Parent',parent,...
                'Style','text',...
                'String','Mid:',...
                'HorizontalAlignment','right');
            smaux.smgui.loopcvars_eth(i,j,4) = uicontrol('Parent',parent,...
                'Style','edit',...
                'String',mean(smscan.loops(i).setchanranges{j}),...
                'HorizontalAlignment','center',...
                'Callback',{@loopcvars_eth_Callback,i,j,4});

            %range
            smaux.smgui.loopcvars_sth(i,j,5) = uicontrol('Parent',parent,...
                'Style','text',...
                'String','Range:',...
                'HorizontalAlignment','right');
            smaux.smgui.loopcvars_eth(i,j,5) = uicontrol('Parent',parent,...
                'Style','edit',...
                'String',smscan.loops(i).setchanranges{j}(2)-smscan.loops(i).setchanranges{j}(1),...
                'HorizontalAlignment','center',...
                'Callback',{@loopcvars_eth_Callback,i,j,5});

            %stepsize
            smaux.smgui.loopcvars_sth(i,j,6) = uicontrol('Parent',parent,...
                'Style','text',...
                'String','Step:',...
                'HorizontalAlignment','right');
            smaux.smgui.loopcvars_eth(i,j,6) = uicontrol('Parent',parent,...
                'Style','edit',...
                'String',(smscan.loops(i).setchanranges{j}(2)-smscan.loops(i).setchanranges{j}(1))/(smscan.loops(i).npoints-1),...
                'HorizontalAlignment','center',...
                'Callback',{@loopcvars_eth_Callback,i,j,6});       
        
            for k=2:6
                set(smaux.smgui.loopcvars_sth(i,j,k),'Position',row.paramLabel(k-1,:));
                set(smaux.smgui.loopcvars_eth(i,j,k),'Position',row.paramEdit(k-1,:));
            end
        end
    elseif j==1 % First setchan when using loop range instead of per-channel ranges
         %minimum
        smaux.smgui.loopcvars_sth(i,j,2) = uicontrol('Parent',parent,...
            'Style','text',...
            'String','Min:',...
            'HorizontalAlignment','right');
        smaux.smgui.loopcvars_eth(i,j,2) = uicontrol('Parent',parent,...
            'Style','edit',...
            'String',smscan.loops(i).rng(1),...
            'HorizontalAlignment','center',...
            'Callback',{@loopcvarsLOCKT_eth_Callback,i,j,2});

        %max
        smaux.smgui.loopcvars_sth(i,j,3) = uicontrol('Parent',parent,...
            'Style','text',...
            'String','Max:',...
            'HorizontalAlignment','right');
        smaux.smgui.loopcvars_eth(i,j,3) = uicontrol('Parent',parent,...
            'Style','edit',...
            'String',smscan.loops(i).rng(2),...
            'HorizontalAlignment','center',...
            'Callback',{@loopcvarsLOCKT_eth_Callback,i,j,3});

        %mid
        smaux.smgui.loopcvars_sth(i,j,4) = uicontrol('Parent',parent,...
            'Style','text',...
            'String','Mid:',...
            'HorizontalAlignment','right');
        smaux.smgui.loopcvars_eth(i,j,4) = uicontrol('Parent',parent,...
            'Style','edit',...
            'String',mean(smscan.loops(i).rng),...
            'HorizontalAlignment','center',...
            'Callback',{@loopcvarsLOCKT_eth_Callback,i,j,4});

        %range
        smaux.smgui.loopcvars_sth(i,j,5) = uicontrol('Parent',parent,...
            'Style','text',...
            'String','Range:',...
            'HorizontalAlignment','right');
        smaux.smgui.loopcvars_eth(i,j,5) = uicontrol('Parent',parent,...
            'Style','edit',...
            'String',smscan.loops(i).rng(2)-smscan.loops(i).rng(1),...
            'HorizontalAlignment','center',...
            'Callback',{@loopcvarsLOCKT_eth_Callback,i,j,5});

        %stepsize
        smaux.smgui.loopcvars_sth(i,j,6) = uicontrol('Parent',parent,...
            'Style','text',...
            'String','Step:',...
            'HorizontalAlignment','right');
        smaux.smgui.loopcvars_eth(i,j,6) = uicontrol('Parent',parent,...
            'Style','edit',...
            'String',(smscan.loops(i).rng(2)-smscan.loops(i).rng(1))/(smscan.loops(i).npoints-1),...
            'HorizontalAlignment','center',...
            'Callback',{@loopcvarsLOCKT_eth_Callback,i,j,6});       

        for k=2:6
            set(smaux.smgui.loopcvars_sth(i,j,k),'Position',row.paramLabel(k-1,:));
            set(smaux.smgui.loopcvars_eth(i,j,k),'Position',row.paramEdit(k-1,:));
        end
    end     


end

% Make the getchannel UI popup objects for loop i
function makeloopgetchans(i, recordStartY)
    global smscan smaux smdata;
    m = smguiLayoutMetrics();
    parent = smaux.smgui.loop_content_ph(i);
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
            selected_names(end+1) = string(chanName); %#ok<AGROW>
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
                    available_names = [current_name; available_names]; %#ok<AGROW>
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
                    debugMsg = [debugMsg sprintf('  %d: %s\n', k, smdata.channels(k).name)]; %#ok<AGROW>
                end
                if length(smdata.channels) > 10
                    debugMsg = [debugMsg sprintf('  ... and %d more channels', length(smdata.channels) - 10)]; %#ok<AGROW>
                end
            else
                debugMsg = [debugMsg '  No channels available - check instrument setup']; %#ok<AGROW>
            end
            
            errordlg(debugMsg, 'Get Channel Lookup Error - Detailed Diagnostics');
            chanval=1;
        end
        recordPos = smguiRecordPopupPosition(j, recordStartY, m);
        smaux.smgui.loopvars_getchans_pmh(i,j) = uicontrol('Parent',parent,...
            'Style','popupmenu',...
            'String',["none"; available_names(:)],...
            'Value',chanval,...
            'HorizontalAlignment','center',...
            'Position',recordPos,...
            'Callback',{@GetChannel,i,j});
    end

    if numgetchans==0, j=0;
    end

    recordPos = smguiRecordPopupPosition(j+1, recordStartY, m);
    smaux.smgui.loopvars_getchans_pmh(i,j+1) = uicontrol('Parent',parent,...
        'Style','popupmenu',...
        'String',["none"; setdiff(channelnames_str, selected_names, "stable")],...
        'Value',1,...
        'HorizontalAlignment','center',...
        'Position',recordPos,...
        'Callback',{@GetChannel,i,j+1});
end

function pos = smguiRecordPopupPosition(j, recordStartY, m)
    idx = j - 1;
    col = mod(idx, m.recordCols);
    row = floor(idx / m.recordCols);
    colStep = m.recordW + m.recordGap;
    pos = [m.recordX + colStep * col, recordStartY - m.rowH * row, m.recordW, m.ctrlH];
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
            scalarNames{end+1} = sprintf("%s_%d", vectorChannelName, i); %#ok<AGROW>
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
