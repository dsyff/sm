classdef instrument_virtual_del_V < virtualInstrumentInterface
    % instrument_virtual_del_V - Minimal virtual channel instrument for del_V mapping.
    %
    % Sets V_tg according to V_tg = V_WSe2 + del_V on the master instrument rack provided at
    % construction time. The instrument exposes a single write-only channel
    % ("del_V") that, when updated, sets V_tg through rackSetWrite.
    %
    % Thomas 20251009

    properties (Constant, Access = private)
        ChannelName string = "del_V";
    end

    properties (Access = private)
        VWSe2ChannelName (1, 1) string = "V_WSe2";
        VTgChannelName (1, 1) string = "V_tg";
    end

    methods

        %% constructor
        function obj = instrument_virtual_del_V(address, masterRack, NameValueArgs)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText};
                masterRack (1, 1) instrumentRack;
                NameValueArgs.VWSe2ChannelName (1, 1) string {mustBeNonzeroLengthText} = "V_WSe2";
                NameValueArgs.VTgChannelName (1, 1) string {mustBeNonzeroLengthText} = "V_tg";
            end

            obj@virtualInstrumentInterface(address, masterRack);
            obj.requireSetCheck = true;

            obj.VWSe2ChannelName = NameValueArgs.VWSe2ChannelName;
            obj.VTgChannelName = NameValueArgs.VTgChannelName;

            obj.addChannel(obj.ChannelName);
        end

    end

    methods (Access = ?instrumentInterface)

        %% REQUIRED OVERRIDES
        function setWriteChannelHelper(obj, channelIndex, setValues)
            switch channelIndex
                case 1
                    delta = obj.extractScalar(setValues, obj.ChannelName);
                    rack = obj.getMasterRack();
                    Vwse2 = rack.rackGet(obj.VWSe2ChannelName);
                    Vwse2Scalar = obj.extractScalar(Vwse2, obj.VWSe2ChannelName);

                    target = Vwse2Scalar + delta;
                    rack.rackSetWrite(obj.VTgChannelName, target);
                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, channelLastSetValues)
            switch channelIndex
                case 1
                    rack = obj.getMasterRack();
                    TF = rack.rackSetCheck(obj.VTgChannelName);
                otherwise
                    TF = setCheckChannelHelper@instrumentInterface(obj, channelIndex, channelLastSetValues);
            end
        end

    end

    methods (Access = private)

        %% helper functions
        function scalar = extractScalar(~, values, channel)
            if ~(isnumeric(values) || islogical(values))
                error("instrument_virtual_del_V:NonNumeric", ...
                    "Channel %s must resolve to numeric values.", channel);
            end
            values = double(values(:));
            if numel(values) ~= 1
                error("instrument_virtual_del_V:BadLength", ...
                    "Channel %s must contain exactly one value.", channel);
            end
            scalar = values;
        end

    end

end
