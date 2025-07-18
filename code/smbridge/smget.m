function varargout = smget(varargin)
% SMGET - Simplified wrapper for smget_new
% 
% This function provides a shorter syntax for accessing smget_new functionality.
% All arguments are passed directly to smget_new for processing.
%
% USAGE:
%   value = smget(channelName)
%   values = smget({channel1, channel2, ...})
%   [val1, val2, ...] = smget(channel1, channel2, ...)
%
% EXAMPLES:
%   x = smget("sr830.X");                    % Single channel
%   xy = smget({"sr830.X", "sr830.Y"});      % Multiple channels as cell array
%   [x, y] = smget("sr830.X", "sr830.Y");    % Multiple channels as separate args
%
% SEE ALSO: smget_new, smset, smrun_new
%
% Thomas 2025-07-17 - Convenience wrapper for faster typing

[varargout{1:nargout}] = smget_new(varargin{:});

end
