classdef (Abstract) virtualInstrumentInterface < instrumentInterface
    % virtualInstrumentInterface - Base class for software-only virtual instruments.
    %
    % Provides shared wiring for virtual instruments tied to an instrumentRack.
    % Enforces write-only semantics by sealing the get helpers and throwing
    % descriptive errors. Nested getting in rack can cause problems, as instruments expects 
    % the same channel to be getWrite and getRead without interruption
    %
    % Thomas 20251009

    properties (Access = protected)
        masterRack instrumentRack {mustBeScalarOrEmpty} = instrumentRack.empty();
    end

    methods
        function obj = virtualInstrumentInterface(address, masterRack)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText};
                masterRack (1, 1) instrumentRack
            end

            obj@instrumentInterface();
            obj.address = address;
            obj.masterRack = masterRack;
            obj.requireSetCheck = false;
        end

        function delete(obj)
            obj.masterRack = instrumentRack.empty();
            delete@instrumentInterface(obj);
        end
    end

    methods (Access = protected)
        function rack = getMasterRack(obj)
            if isempty(obj.masterRack) || ~isvalid(obj.masterRack)
                error("virtualInstrumentInterface:MissingMasterRack", ...
                    "The master instrument rack reference is missing or invalid.");
            end
            rack = obj.masterRack;
        end
    end

    methods (Access = ?instrumentInterface, Sealed)
        function getWriteChannelHelper(obj, channelIndex)
            channelName = obj.channelTable.channels(channelIndex);
            error("virtualInstrumentInterface:GetUnsupported", ...
                "Virtual channel %s does not support get operations.", channelName);
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            error("virtualInstrumentInterface:GetUnsupported", ...
                "Virtual channels do not support get operations.");
        end
    end
end
