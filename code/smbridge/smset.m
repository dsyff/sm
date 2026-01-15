function smset(varargin)
% SMSET - Simplified wrapper for smset_new
%
% This function provides a shorter syntax for accessing smset_new functionality.
% All arguments are passed directly to smset_new for processing.
%
% USAGE:
%   smset(channelName, value)
%   smset(["channel1", "channel2", ...], [value1; value2; ...])
%
% EXAMPLES:
%   smset("sr830.frequency", 1000);                    % Single channel
%   smset(["k2400.V_source", "sr830.sensitivity"], [5; 1e-6]);  % Multiple channels
%
% NOTES:
%   - Uses same setWrite/setCheck optimization as smset_new
%   - Automatically verifies values within defined tolerances
%   - Supports all channel types (scalar and vector)
%
% SEE ALSO: smset_new, smget, smrun_new
%
% Thomas 2025-07-17 - Convenience wrapper for faster typing

smset_new(varargin{:});

end
