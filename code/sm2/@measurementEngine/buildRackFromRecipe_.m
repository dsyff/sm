function rack = buildRackFromRecipe_(recipe, spawnOnClientFcn)
    if nargin < 2
        spawnOnClientFcn = [];
    end

    rack = instrumentRack(true);
    if isempty(spawnOnClientFcn)
        rack.tryTimes = inf;
    else
        rack.tryTimes = 1;
    end
    assignin("base", "rack", rack);
    if isempty(spawnOnClientFcn)
        assignin("base", "sm_spawnOnClient", []);
    else
        assignin("base", "sm_spawnOnClient", spawnOnClientFcn);
    end

    virtualSteps = struct([]);
    if isprop(recipe, "virtualInstrumentSteps")
        virtualSteps = recipe.virtualInstrumentSteps;
    end
    virtualNames = string.empty(0, 1);
    if ~isempty(virtualSteps)
        virtualNames = string({virtualSteps.friendlyName});
        if isrow(virtualNames)
            virtualNames = virtualNames.';
        end
    end

    if ~isempty(recipe.statements)
        statementTargets = string({recipe.statements.instrumentFriendlyName});
        allInstrumentNames = [string({recipe.instrumentSteps.friendlyName}), string({virtualSteps.friendlyName})];
        badStatementTarget = ~ismember(statementTargets, allInstrumentNames);
        if any(badStatementTarget)
            bad = unique(statementTargets(badStatementTarget));
            error("measurementEngine:RecipeStatementsUnresolved", ...
                "Statement steps refer to instrument(s) that were not constructed: %s", strjoin(bad, ", "));
        end
    end

    pendingChannel = true(1, numel(recipe.channelSteps));
    pendingVirtualChannel = false(1, numel(recipe.channelSteps));
    for k = 1:numel(recipe.channelSteps)
        step = recipe.channelSteps(k);
        pendingVirtualChannel(k) = any(step.instrumentFriendlyName == virtualNames);
    end

    % Build hardware instruments one by one.
    for k = 1:numel(recipe.instrumentSteps)
        step = recipe.instrumentSteps(k);
        experimentContext.print("Setting up instrument %s ...", step.friendlyName);
        className = step.className;
        ctorArgs = step.positionalArgs;
        nv = step.nameValuePairs;
        if ~iscell(ctorArgs)
            ctorArgs = {ctorArgs};
        end
        if ~iscell(nv)
            nv = {nv};
        end
        inst = feval(className, ctorArgs{:}, nv{:});
        inst.validateWorkersRequestedFromRecipe(double(step.numeWorkersRequested));
        assignin("base", char(step.handleVar), inst);
        rack.addInstrument(inst, step.friendlyName);

        for chIdx = 1:numel(recipe.channelSteps)
            if ~pendingChannel(chIdx) || pendingVirtualChannel(chIdx)
                continue;
            end
            chStep = recipe.channelSteps(chIdx);
            if chStep.instrumentFriendlyName ~= step.friendlyName
                continue;
            end
            rack.addChannel( ...
                chStep.instrumentFriendlyName, ...
                chStep.channel, ...
                chStep.channelFriendlyName, ...
                chStep.rampRates, ...
                chStep.rampThresholds, ...
                chStep.softwareMins, ...
                chStep.softwareMaxs);
            pendingChannel(chIdx) = false;
        end

        runStatementsForInstrument_(step.friendlyName);
    end

    % Build virtual instruments (they receive the master rack during construction),
    % then add their channels.
    for vIdx = 1:numel(virtualSteps)
        step = virtualSteps(vIdx);
        experimentContext.print("Setting up instrument %s ...", step.friendlyName);
        className = step.className;
        ctorArgs = step.positionalArgs;
        nv = step.nameValuePairs;
        if ~iscell(ctorArgs)
            ctorArgs = {ctorArgs};
        end
        if isempty(ctorArgs)
            ctorArgs = {step.friendlyName};
        end
        if ~iscell(nv)
            nv = {nv};
        end

        inst = feval(className, ctorArgs{1}, rack, ctorArgs{2:end}, nv{:});
        inst.validateWorkersRequestedFromRecipe(double(step.numeWorkersRequested));
        assignin("base", char(step.handleVar), inst);
        rack.addInstrument(inst, step.friendlyName);

        for k = 1:numel(recipe.channelSteps)
            if ~pendingChannel(k)
                continue;
            end
            chStep = recipe.channelSteps(k);
            if chStep.instrumentFriendlyName ~= step.friendlyName
                continue;
            end
            rack.addChannel( ...
                chStep.instrumentFriendlyName, ...
                chStep.channel, ...
                chStep.channelFriendlyName, ...
                chStep.rampRates, ...
                chStep.rampThresholds, ...
                chStep.softwareMins, ...
                chStep.softwareMaxs);
            pendingChannel(k) = false;
        end

        runStatementsForInstrument_(step.friendlyName);
    end
    if any(pendingChannel)
        bad = string({recipe.channelSteps(pendingChannel).instrumentFriendlyName});
        bad = unique(bad(:));
        error("measurementEngine:RecipeChannelsUnresolved", ...
            "Channel steps refer to instrument(s) that were not constructed: %s", strjoin(bad, ", "));
    end

    rack.flush();

    function runStatementsForInstrument_(instrumentFriendlyName)
        if isempty(recipe.statements)
            return;
        end
        for statementIdx = 1:numel(recipe.statements)
            step = recipe.statements(statementIdx);
            if step.instrumentFriendlyName ~= instrumentFriendlyName
                continue;
            end
            evalin("base", char(step.codeString));
        end
    end
end

