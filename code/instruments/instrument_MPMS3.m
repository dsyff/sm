classdef instrument_MPMS3 < instrumentInterface
    properties (Access = private)
        temperatureStatus
        fieldStatus
        fieldApproach
        temperatureApproach
        fieldMode
        readValues
    end

    methods
        function obj = instrument_MPMS3(address, port)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText}
                port (1, 1) uint16 = uint16(11000)
            end

            obj@instrumentInterface();

            classFile = which(class(obj));
            if strlength(classFile) == 0
                error("instrument_MPMS3:ClassLookupFailed", ...
                    "Unable to locate instrument_MPMS3.m via which(class(obj)).");
            end
            repoRoot = fileparts(fileparts(fileparts(classFile)));
            assemblyPath = fullfile(repoRoot, "legacy", "legacy sm complete", ...
                "SpecialMeasure", "QMInstruments", "MPMS3", "QDInstrument.dll");
            if ~isfile(assemblyPath)
                error("instrument_MPMS3:MissingAssembly", ...
                    "QDInstrument.dll not found at %s.", assemblyPath);
            end

            assemblyFile = NET.addAssembly(assemblyPath);
            handleInstrumentType = assemblyFile.AssemblyHandle.GetType( ...
                "QuantumDesign.QDInstrument.QDInstrumentBase+QDInstrumentType");
            instrumentType = handleInstrumentType.GetEnumValues().Get(3); % SVSM / MPMS3
            handle = QuantumDesign.QDInstrument.QDInstrumentFactory.GetQDInstrument( ...
                instrumentType, true, address, port);

            handleTemperatureStatus = assemblyFile.AssemblyHandle.GetType( ...
                "QuantumDesign.QDInstrument.QDInstrumentBase+TemperatureStatus");
            obj.temperatureStatus = System.Activator.CreateInstance(handleTemperatureStatus);

            handleFieldStatus = assemblyFile.AssemblyHandle.GetType( ...
                "QuantumDesign.QDInstrument.QDInstrumentBase+FieldStatus");
            obj.fieldStatus = System.Activator.CreateInstance(handleFieldStatus);

            handleFieldApproach = assemblyFile.AssemblyHandle.GetType( ...
                "QuantumDesign.QDInstrument.QDInstrumentBase+FieldApproach");
            obj.fieldApproach = System.Activator.CreateInstance(handleFieldApproach);

            handleTemperatureApproach = assemblyFile.AssemblyHandle.GetType( ...
                "QuantumDesign.QDInstrument.QDInstrumentBase+TemperatureApproach");
            obj.temperatureApproach = System.Activator.CreateInstance(handleTemperatureApproach);

            handleFieldMode = assemblyFile.AssemblyHandle.GetType( ...
                "QuantumDesign.QDInstrument.QDInstrumentBase+FieldMode");
            obj.fieldMode = System.Activator.CreateInstance(handleFieldMode);

            obj.address = address + ":" + string(port);
            obj.communicationHandle = handle;

            obj.addChannel("T");
            obj.addChannel("B");
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(obj, channelIndex)
            handle = obj.communicationHandle;
            switch channelIndex
                case 1
                    [~, obj.readValues, obj.temperatureStatus] = handle.GetTemperature(0, obj.temperatureStatus);
                case 2
                    [~, obj.readValues, obj.fieldStatus] = handle.GetField(0, obj.fieldStatus);
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            switch channelIndex
                case {1, 2}
                    getValues = obj.readValues;
            end
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            handle = obj.communicationHandle;
            switch channelIndex
                case 1
                    handle.SetTemperature(setValues, 20, obj.temperatureApproach);
                case 2
                    handle.SetField(setValues, 150, obj.fieldApproach, obj.fieldMode);
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, ~)
            handle = obj.communicationHandle;
            switch channelIndex
                case 1
                    [~, ~, obj.temperatureStatus] = handle.GetTemperature(0, obj.temperatureStatus);
                    TF = (string(obj.temperatureStatus) == "Stable");
                case 2
                    [~, ~, obj.fieldStatus] = handle.GetField(0, obj.fieldStatus);
                    TF = (string(obj.fieldStatus) == "StablePersistent");
            end
        end
    end
end
