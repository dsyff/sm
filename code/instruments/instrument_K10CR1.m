classdef instrument_K10CR1 < instrumentInterface
    % Thorlabs K10CR1 Cage Rotator controller
    % Modern instrument driver migrated from legacy specialmeasure implementation
    % Provides single channel "position_deg" for reading/setting angular position

    properties (Constant, Access = private)
        DEVICE_UNITS_PER_REVOLUTION = 49152000; % device encoder counts per full revolution
        DEFAULT_MOVE_TIMEOUT_MS = uint32(60000); % 60 seconds, matches legacy driver
        POLL_PERIOD_MS = uint32(250);
    end

    properties (Access = private)
        pendingPositionDegrees double = NaN;
        moveTimeoutMs (1, 1) uint32 = instrument_K10CR1.DEFAULT_MOVE_TIMEOUT_MS;
    end

    methods

        function obj = instrument_K10CR1(serialNumber, NameValueArgs)
            arguments
                serialNumber (1, 1) string = "";
                NameValueArgs.MoveTimeout (1, 1) uint32 = instrument_K10CR1.DEFAULT_MOVE_TIMEOUT_MS;
            end

            obj@instrumentInterface();
            obj.requireSetCheck = true;
            obj.setTimeout = minutes(double(NameValueArgs.MoveTimeout) / 60000); % convert ms to minutes
            obj.setInterval = seconds(0.25);
            obj.moveTimeoutMs = NameValueArgs.MoveTimeout;

            obj.loadKinesisAssemblies();

            % Create and connect to the hardware
            [deviceHandle, resolvedSerial] = obj.createAndConnectDevice(serialNumber, NameValueArgs.MoveTimeout);

            % Assign object properties
            obj.address = resolvedSerial;
            obj.communicationHandle = deviceHandle;

            % Configure channel(s)
            obj.addChannel("position_deg", setTolerances = 1E-3); % 1 millidegree default tolerance when checking position
        end

        function delete(obj)
            try
                if ~isempty(obj.communicationHandle)
                    StopPolling(obj.communicationHandle);
                    Disconnect(obj.communicationHandle);
                    % Some Kinesis .NET objects expose Dispose()
                    if ismethod(obj.communicationHandle, "Dispose")
                        Dispose(obj.communicationHandle);
                    end
                end
            catch driverError
                warning("instrument_K10CR1:delete", "Failed to fully dispose device: %s", driverError.message);
            end
        end

        function flush(obj) %#ok<MANU>
            % No buffered communication to flush for Kinesis .NET API
        end

        function home(obj, timeoutMs)
            % Homes the stage and waits for completion
            arguments
                obj;
                timeoutMs (1, 1) uint32 = instrument_K10CR1.DEFAULT_MOVE_TIMEOUT_MS;
            end
            handle = obj.communicationHandle;
            obj.ensureConnected();
            Home(handle, timeoutMs);
        end

    end

    methods (Access = ?instrumentInterface)

        function getWriteChannelHelper(obj, ~)
            % For K10CR1 the read is non-blocking; capture value here for consistency
            obj.pendingPositionDegrees = obj.readPositionDegrees();
        end

        function getValues = getReadChannelHelper(obj, ~)
            getValues = obj.pendingPositionDegrees;
            obj.pendingPositionDegrees = NaN;
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            switch channelIndex
                case 1 % position_deg
                    obj.ensureConnected();
                    desiredDegrees = setValues(1);
                    targetUnits = obj.degreesToDeviceUnits(desiredDegrees);
                    MoveTo_DeviceUnit(obj.communicationHandle, targetUnits, obj.moveTimeoutMs);
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, channelLastSetValues)
            switch channelIndex
                case 1 % position_deg
                    currentDegrees = obj.readPositionDegrees();
                    tolerance = obj.setTolerances{channelIndex};
                    TF = all(abs(currentDegrees - channelLastSetValues) <= tolerance);
            end
        end

    end

    methods (Access = private)

        function ensureConnected(obj)
            assert(~isempty(obj.communicationHandle), "K10CR1 device is not connected.");
        end

        function loadKinesisAssemblies(~)
            persistent assembliesLoaded;
            if ~isempty(assembliesLoaded) && assembliesLoaded
                return;
            end

            try
                basePath = "C:\Program Files\Thorlabs\Kinesis\";
                NET.addAssembly(basePath + "Thorlabs.MotionControl.DeviceManagerCLI.dll");
                NET.addAssembly(basePath + "Thorlabs.MotionControl.IntegratedStepperMotorsCLI.dll");
                assembliesLoaded = true;
            catch assemblyError
                error("instrument_K10CR1:AssemblyLoad", "Failed to load Thorlabs Kinesis assemblies from the default installation: %s", assemblyError.message);
            end
        end

    function [deviceHandle, resolvedSerial] = createAndConnectDevice(~, serialNumber, moveTimeout)
            try
                DeviceManagerCLI = Thorlabs.MotionControl.DeviceManagerCLI.DeviceManagerCLI;
                DeviceManagerCLI.BuildDeviceList();
                prefix = Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.DevicePrefix;
                deviceList = DeviceManagerCLI.GetDeviceList(prefix);
            catch deviceQueryError
                error("instrument_K10CR1:DeviceQuery", "Unable to enumerate K10CR1 devices: %s", deviceQueryError.message);
            end

            if deviceList.Count == 0
                error("instrument_K10CR1:NoDevices", "No K10CR1 cage rotators detected. Ensure device is connected and no other session is using it.");
            end

            if strlength(serialNumber) == 0
                resolvedSerial = string(deviceList.Item(0));
            else
                resolvedSerial = string(serialNumber);
            end

            if ~deviceList.Contains(resolvedSerial)
                error("instrument_K10CR1:SerialNotFound", "Requested serial %s not found among connected devices.", resolvedSerial);
            end

            try
                deviceHandle = Thorlabs.MotionControl.IntegratedStepperMotorsCLI.CageRotator.CreateCageRotator(resolvedSerial);
                Connect(deviceHandle, resolvedSerial);
                StartPolling(deviceHandle, instrument_K10CR1.POLL_PERIOD_MS);
                ResetStageToDefaults(deviceHandle);
                pause(0.5);

                if ~IsSettingsInitialized(deviceHandle)
                    WaitForSettingsInitialized(deviceHandle, moveTimeout);
                end
                pause(0.5);

                EnableDevice(deviceHandle);
                pause(0.5);
                Home(deviceHandle, moveTimeout);
                pause(0.5);
            catch connectError
                error("instrument_K10CR1:Connect", "Failed to initialize K10CR1 with serial %s: %s", resolvedSerial, connectError.message);
            end
        end

        function degrees = readPositionDegrees(obj)
            obj.ensureConnected();
            positionDeviceUnits = double(GetPositionCounter(obj.communicationHandle));
            degrees = positionDeviceUnits * 360 / instrument_K10CR1.DEVICE_UNITS_PER_REVOLUTION;
        end

        function deviceUnits = degreesToDeviceUnits(~, degrees)
            turns = degrees / 360;
            deviceUnitsFloat = turns * instrument_K10CR1.DEVICE_UNITS_PER_REVOLUTION;
            deviceUnits = uint32(round(deviceUnitsFloat));
        end

    end

end
