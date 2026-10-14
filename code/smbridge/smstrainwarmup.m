function smstrainwarmup()
%SMSTRAINWARMUP Zero strain controls, warm up, then pump down (3 purges, no bake).
% Waits up to 6 hours for WarmingUp -> Ready; returns after pump down starts.

global engine %#ok<GVMIS>

if ~exist("engine", "var") || isempty(engine) || ~isa(engine, "measurementEngine")
    error("smstrainwarmup:MissingEngine", ...
        "measurementEngine not found. Please run smready(...) first.");
end

engine.rackSet(["activeControl"; "V_str_i"; "V_str_o"], zeros(3, 1));
engine.evalOnEngine("handle_strainController.warmup()");
experimentContext.print("Strain warmup started; waiting for Montana Ready before pump down.");
deadline = datetime("now") + hours(6);
warmupStarted = false;
while true
    state = engine.evalOnEngine("handle_strainController.getCryostatState()");
    warmupStarted = warmupStarted || state == "WarmingUp";
    if warmupStarted && state == "Ready"
        break;
    end
    if datetime("now") >= deadline
        error("smstrainwarmup:WarmupTimeout", "Montana did not complete WarmingUp -> Ready within 6 hours.");
    end
    pause(5);
end
engine.evalOnEngine("handle_strainController.pumpdown()");
experimentContext.print("Montana pump down started: 3 nitrogen purges, no bakeout.");
end
