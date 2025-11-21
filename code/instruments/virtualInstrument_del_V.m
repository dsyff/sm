classdef virtualInstrument_del_V < virtualInstrumentInterface
    % instrument_virtual_del_V - Minimal virtual channel instrument for del_V mapping.
    %
    % Sets V_set according to V_set = V_get + del_V on the master instrument rack provided at
    % construction time. The instrument exposes a single write-only channel
    % ("del_V") that, when updated, sets V_set through rackSetWrite.
    %
    % Thomas 20251009

    properties
        vGetChannelName (1, 1) string;
        vSetChannelName (1, 1) string;
    end

    methods

        %% constructor
        function obj = virtualInstrument_del_V(address, masterRack, NameValueArgs)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText};
                masterRack (1, 1) instrumentRack;
                NameValueArgs.vGetChannelName (1, 1) string;
                NameValueArgs.vSetChannelName (1, 1) string;
            end

            obj@virtualInstrumentInterface(address, masterRack);
            obj.requireSetCheck = true;

            obj.vGetChannelName = NameValueArgs.vGetChannelName;
            obj.vSetChannelName = NameValueArgs.vSetChannelName;

            obj.addChannel("del_V");
        end

    end

    methods (Access = ?instrumentInterface)

        %% REQUIRED OVERRIDES
        function setWriteChannelHelper(obj, channelIndex, setValues)
            switch channelIndex
                case 1
                    % setWriteChannel (instrumentInterface) already validated this single-value
                    % channel and enforced a column double, so we can consume the scalar directly.
                    delV = setValues(1);
                    rack = obj.getMasterRack();
                    vGet = rack.rackGet(obj.vGetChannelName);
                    % LLM note: rackGet validates channel sizes and returns the correct numeric shape,
                    % so an additional extractScalar call here would be redundant.
                    vSetTarget = vGet + delV;
                    rack.rackSetWrite(obj.vSetChannelName, vSetTarget);
                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, channelLastSetValues)
            switch channelIndex
                case 1
                    rack = obj.getMasterRack();
                    TF = rack.rackSetCheck(obj.vSetChannelName);
                otherwise
                    TF = setCheckChannelHelper@instrumentInterface(obj, channelIndex, channelLastSetValues);
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            switch channelIndex
                case 1
                    rack = obj.getMasterRack();
                    vSet = rack.rackGet(obj.vSetChannelName);
                    vGet = rack.rackGet(obj.vGetChannelName);
                    getValues = vSet - vGet;
            end
        end

    end

end
