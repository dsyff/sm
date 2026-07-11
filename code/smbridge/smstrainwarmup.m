function smstrainwarmup()
%SMSTRAINWARMUP Zero strain-cell controls, then start cryostat warmup.

global engine %#ok<GVMIS>

if ~exist("engine", "var") || isempty(engine) || ~isa(engine, "measurementEngine")
    error("smstrainwarmup:MissingEngine", ...
        "measurementEngine not found. Please run smready(...) first.");
end

engine.rackSet(["activeControl"; "V_str_i"; "V_str_o"], zeros(3, 1));
engine.evalOnEngine("handle_strainController.warmup()");
end
