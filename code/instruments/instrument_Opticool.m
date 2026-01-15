classdef instrument_Opticool < instrumentInterface
    % Thomas 20241221
    properties (Access = private)
        % class variables go here

        temperatureStatus;
        fieldStatus;
        fieldApproach;
        temperatureApproach;
        fieldMode;

        readValues;
    end

    methods

        function obj = instrument_Opticool(address)
            obj@instrumentInterface();
            assemblyFile = NET.addAssembly('C:\QdOptiCool\LabVIEW\QDInstrument.dll');
            handle_instrumentType = assemblyFile.AssemblyHandle.GetType('QuantumDesign.QDInstrument.QDInstrumentBase+QDInstrumentType');
            instrumentType = handle_instrumentType.GetEnumValues().Get(4); 
            handle = QuantumDesign.QDInstrument.QDInstrumentFactory.GetQDInstrument(instrumentType, false, address);

            handle_temperatureStatus = assemblyFile.AssemblyHandle.GetType('QuantumDesign.QDInstrument.QDInstrumentBase+TemperatureStatus');
            obj.temperatureStatus = System.Activator.CreateInstance(handle_temperatureStatus);

            handle_fieldStatus = assemblyFile.AssemblyHandle.GetType('QuantumDesign.QDInstrument.QDInstrumentBase+FieldStatus');
            obj.fieldStatus = System.Activator.CreateInstance(handle_fieldStatus);

            handle_fieldApproach = assemblyFile.AssemblyHandle.GetType('QuantumDesign.QDInstrument.QDInstrumentBase+FieldApproach');
            obj.fieldApproach = System.Activator.CreateInstance(handle_fieldApproach);
            %obj.fieldApproach = QuantumDesign.QDInstrument.FieldApproach.Linear;

            handle_temperatureApproach = assemblyFile.AssemblyHandle.GetType('QuantumDesign.QDInstrument.QDInstrumentBase+TemperatureApproach');
            obj.temperatureApproach = System.Activator.CreateInstance(handle_temperatureApproach);
            %obj.temperatureApproach = QuantumDesign.QDInstrument.TemperatureApproach.FastSettle;

            handle_fieldMode = assemblyFile.AssemblyHandle.GetType('QuantumDesign.QDInstrument.QDInstrumentBase+FieldMode');
            obj.fieldMode = System.Activator.CreateInstance(handle_fieldMode);
            %obj.fieldMode = QuantumDesign.QDInstrument.FieldMode.Driven;
            %obj.fieldMode = QuantumDesign.QDInstrument.FieldMode.Persistent;

            % assign object properties
            obj.address = address;
            obj.communicationHandle = handle;

            obj.addChannel("T");
            obj.addChannel("B");
        end

        % function cooldown(obj)
        % end

        % function warmup(obj)
        % end

        function currentTarget = getCurrentTargetTemperature(obj)
            [~, currentTarget, ~, ~] = obj.communicationHandle.GetTemperatureSetpoints(0, 0, 0);
        end
        
        function currentTarget = getCurrentTargetMagneticField(obj)
            [~, currentTarget, ~, ~, ~] = obj.communicationHandle.GetFieldSetpoints(0, 0, 0, 0);
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
                    handle.SetTemperature(setValues, 50, obj.temperatureApproach);
                case 2
                    handle.SetField(setValues, 110, obj.fieldApproach, obj.fieldMode);
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, channelLastSetValues)
            handle = obj.communicationHandle;
            switch channelIndex
                case 1
                    targetTemperature = channelLastSetValues;
                    if obj.enforceTargetTemperature(targetTemperature)
                        %warning("Opticool target temperature was changed elsewhere.");
                    end

                    [~, obj.readValues, obj.temperatureStatus] = handle.GetTemperature(0, obj.temperatureStatus);
                    TF = (string(obj.temperatureStatus) == "Stable");
                case 2
                    %GetFieldSetpoints is not working, so we cannot check if the target magnetic field was changed elsewhere.
                    %targetMagneticField = channelLastSetValues;
                    %if obj.enforceTargetMagneticField(targetMagneticField)
                    %    warning("Opticool target magnetic field was changed elsewhere.");
                    %end

                    [~, obj.readValues, obj.fieldStatus] = handle.GetField(0, obj.fieldStatus);
                    TF = (string(obj.fieldStatus) == "StableDriven");
            end
        end

    end

    methods (Access = private)

        function targetChanged = enforceTargetTemperature(obj, targetTemperature)
            % sets temperature if current target differs from
            % targetTemperature
            currentTarget = obj.getCurrentTargetTemperature();
            targetChanged = abs(currentTarget - targetTemperature) > 1E-3;
            if targetChanged
                obj.setWriteChannel("T", targetTemperature);
            end
        end

        function targetChanged = enforceTargetMagneticField(obj, targetMagneticField)
            currentTarget = obj.getCurrentTargetMagneticField();
            targetChanged = abs(currentTarget - targetMagneticField) > 1E-3;
            if targetChanged
                obj.setWriteChannel("B", targetMagneticField);
            end
        end
    end

end