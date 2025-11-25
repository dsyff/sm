classdef instrument_demo < instrumentInterface
    % Thomas 20241221
    % only numeric values are allowed as channels. non-numeric values
    % should be made into class methods.
    %#ok<*NASGU>
    %#ok<*INUSD>

    properties (Access = private)
        % class variables go here
    end

    methods

        %% constructor goes here. rename to match class name
        function obj = instrument_demo(address)
            obj@instrumentInterface();
            handle = [];

            % assign object properties
            obj.address = address;
            obj.communicationHandle = handle;

            % add channels here. channelSize is how many inputs/outputs the
            % channel has. Set channelSize to 1 if only one value at a time
            % is handled by the channel
            obj.addChannel("channelName1", setTolerances = 1e-3);
            obj.addChannel("channelName2");
            obj.addChannel("channelName3DualInputOutput", 2, setTolerances = [1e-3; 1e-3]);
            obj.addChannel("channelName4TriInputOutput", 3, setTolerances = [1;1;1]*1E-8);
        end

        %% destructor; override according to needs
        % if no need to override, simply remove these functions. below are
        % the default implementations in the instrument abstract superclass
        % definition
        function delete(obj)
            %Gracefully closes connection to instrument. Many instruments
            %requires overriding this default implementation. This
            %implementation is redundant but serves as an example
            delete(obj.communicationHandle);
        end

    end

    methods (Access = ?instrumentInterface)

        %% REQUIRED METHODS - must implement these two methods

        function getWriteChannelHelper(obj, channelIndex)
            % Send commands to instrument - separated from reading for optimal batching
            % This allows instrumentRack to minimize reading time by sending all
            % getWrite commands first, then reading all results in sequence.
            % Many instruments need time to physically settle after receiving commands.
            %
            % Note: channelIndex is guaranteed to be a valid index of a channel
            % in obj.channelTable.
            handle = obj.communicationHandle;
            switch channelIndex
                case 1
                    % Send command to instrument, e.g.:
                    % writeline(handle, 'MEAS:VOLT?');
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            % Read responses from instrument - called after getWriteChannelHelper
            % getValues should preferably be a column vector
            %
            % Note: channelIndex is guaranteed to be a valid index of a channel
            % in obj.channelTable.
            handle = obj.communicationHandle;
            switch channelIndex
                case 1
                    % Read response from instrument, e.g.:
                    % getValues = str2double(strip(readline(handle)));
                    getValues = 1;
            end
        end

        %% OPTIONAL OVERRIDE METHODS - remove if not needed

        function setWriteChannelHelper(obj, channelIndex, setValues)
            % Send set commands to instrument - separated from verification for optimal batching
            % This allows instrumentRack to send all set commands first, then verify
            % all values have settled in batch. Critical for slow-settling instruments.
            % setValues is a column vector
            %
            % Note: channelIndex is guaranteed to be a valid index of a channel
            % in obj.channelTable. setValues is guaranteed to be a column vector
            % of the correct size for the channel, and contains no NaNs.
            handle = obj.communicationHandle;
            switch channelIndex
                case 1
                    % Send set command to instrument, e.g.:
                    % writeline(handle, sprintf('VOLT %g', setValues));
                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end



    end

    methods (Access = private)
        %% helper functions to be used by this class only
    end

end