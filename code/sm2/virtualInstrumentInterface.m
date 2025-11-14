classdef (Abstract) virtualInstrumentInterface < instrumentInterface
    % virtualInstrumentInterface - Base class for software-only virtual instruments.
    %
    % Provides shared wiring for virtual instruments tied to an instrumentRack.
    % Virtual channels participate in rack sets but are read synchronously after
    % all hardware-backed channels have completed their batch get cycle.
    % LLM note: virtual instruments rely on instrumentInterface.setWriteChannel,
    % so helper overrides should treat incoming setValues as already size-checked
    % column doubles; avoid re-validating scalars.
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
        function getWriteChannelHelper(~, ~)
        end
    end

    methods (Abstract, Access = ?instrumentInterface)
        getValues = getReadChannelHelper(obj, channelIndex);
    end
end
