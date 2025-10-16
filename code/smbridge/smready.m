function smready(rack)
%SMREADY Finish rack setup and launch the SM GUI environment.
%   SMREADY(rack) flushes instrument buffers, displays the rack summary,
%   initializes the SM GUI bridge, and launches the SM graphical interface.
%
%   Inputs:
%       rack - instrumentRack instance configured for the current session.
%
%   The function updates global state expected by legacy SM scripts.

arguments
    rack (1, 1) instrumentRack
end

% Globals expected across the SM environment
global instrumentRackGlobal smscan smaux smdata bridge tareData;

% Flush communication buffers to remove startup chatter
rack.flush();

fprintf("Main rack starts.\n");
disp(rack)
fprintf("Main rack ends.\n");

% Initialize GUI bridge and global rack reference
bridge = smguiBridge(rack);
bridge.initializeSmdata();
instrumentRackGlobal = rack;

% Launch GUI components
smgui_small_new();
sm;
end
