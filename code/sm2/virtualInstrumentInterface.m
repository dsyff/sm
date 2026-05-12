classdef (Abstract) virtualInstrumentInterface < instrumentInterface
    % virtualInstrumentInterface - Base class for software-only virtual instruments.
    %
    % Provides shared wiring for virtual instruments tied to an instrumentRackProxy.
    % Virtual channels participate in rack sets but are read synchronously after
    % all hardware-backed channels have completed their batch get cycle.
    % LLM note: virtual instruments rely on instrumentInterface.setWriteChannel,
    % so helper overrides should treat incoming setValues as already size-checked
    % column doubles; avoid re-validating scalars.
    %
    % Thomas 20251009

    properties (Access = protected)
        masterRackProxy instrumentRackProxy {mustBeScalarOrEmpty} = instrumentRackProxy.empty();
    end

    methods
        function obj = virtualInstrumentInterface(address, masterRackProxy)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText};
                masterRackProxy (1, 1) instrumentRackProxy
            end

            obj@instrumentInterface();
            obj.address = address;
            obj.masterRackProxy = masterRackProxy;
        end

        function delete(obj)
            obj.masterRackProxy = instrumentRackProxy.empty();
            delete@instrumentInterface(obj);
        end
    end

    methods (Access = protected)
        function masterRackProxy = getMasterRackProxy(obj)
            if isempty(obj.masterRackProxy) || ~isvalid(obj.masterRackProxy)
                error("virtualInstrumentInterface:MissingMasterRack", ...
                    "The master instrument rack proxy reference is missing or invalid.");
            end
            masterRackProxy = obj.masterRackProxy;
        end
    end

    methods (Access = ?instrumentInterface, Sealed)
        function getWriteChannelHelper(~, ~)
        end
    end

    methods (Access = ?instrumentInterface)
        function TF = setCheckChannelHelper(~, ~, ~)
            TF = true;
        end
    end

    methods (Abstract, Access = ?instrumentInterface)
        getValues = getReadChannelHelper(obj, channelIndex);
    end
end
