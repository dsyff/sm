classdef (Sealed) instrumentRackProxy < handle
    % instrumentRackProxy - Narrow rack API exposed to virtual instruments.

    properties (Access = private)
        masterRack instrumentRack {mustBeScalarOrEmpty} = instrumentRack.empty();
    end

    methods
        function obj = instrumentRackProxy(masterRack)
            arguments
                masterRack (1, 1) instrumentRack
            end
            obj.masterRack = masterRack;
        end

        function delete(obj)
            obj.masterRack = instrumentRack.empty();
        end

        function getValues = rackGet(obj, channelFriendlyNames)
            getValues = obj.getMasterRack().rackGet(channelFriendlyNames);
        end

        function rackSetWrite(obj, channelFriendlyNames, setValues)
            obj.getMasterRack().rackSetWrite(channelFriendlyNames, setValues);
        end

        function rackSet(obj, channelFriendlyNames, setValues)
            obj.getMasterRack().rackSet(channelFriendlyNames, setValues);
        end

        function TF = rackSetCheck(obj, channelFriendlyNames)
            TF = obj.getMasterRack().rackSetCheck(channelFriendlyNames);
        end

        function assertChannelsExist(obj, channelFriendlyNames)
            channelFriendlyNames = unique(string(channelFriendlyNames(:)));
            available = obj.getMasterRack().channelTable.channelFriendlyNames;
            missing = channelFriendlyNames(~ismember(channelFriendlyNames, available));
            if ~isempty(missing)
                error("instrumentRackProxy:MissingRackChannels", ...
                    "These rack channels are missing: %s", strjoin(missing, ", "));
            end
        end

        function instrument = getReviewedInstrumentHandleForNonChannelMethod(obj, instrumentFriendlyName, expectedClass, purpose)
            arguments
                obj
                instrumentFriendlyName (1, 1) string {mustBeNonzeroLengthText}
                expectedClass (1, 1) string = ""
                purpose (1, 1) string = "non-channel method access"
            end

            instrumentTable = obj.getMasterRack().instrumentTable;
            mask = instrumentTable.instrumentFriendlyNames == instrumentFriendlyName;
            if ~any(mask)
                error("instrumentRackProxy:MissingInstrument", ...
                    "Instrument ""%s"" not found while requesting %s.", instrumentFriendlyName, purpose);
            end

            instrument = instrumentTable.instruments(find(mask, 1, "first"));
            if ~isvalid(instrument)
                error("instrumentRackProxy:InvalidInstrumentHandle", ...
                    "Instrument ""%s"" is invalid while requesting %s.", instrumentFriendlyName, purpose);
            end
            if strlength(expectedClass) > 0 && ~isa(instrument, expectedClass)
                error("instrumentRackProxy:UnexpectedInstrumentClass", ...
                    "Instrument ""%s"" must be a %s for %s.", instrumentFriendlyName, expectedClass, purpose);
            end
        end
    end

    methods (Access = private)
        function masterRack = getMasterRack(obj)
            if isempty(obj.masterRack) || ~isvalid(obj.masterRack)
                error("instrumentRackProxy:MissingMasterRack", ...
                    "The master instrument rack reference is missing or invalid.");
            end
            masterRack = obj.masterRack;
        end
    end
end
