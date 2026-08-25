function smQueueBindEngine(engine)
%SMQUEUEBINDENGINE Refresh queue state/view from observable engine lifecycle.
%#ok<*GVMIS>

global smaux

if nargin ~= 1 || isempty(engine) || ~isa(engine, "measurementEngine") || ~isvalid(engine)
    error("smQueueBindEngine:InvalidEngine", "A valid measurementEngine is required.");
end
state = smQueueState.get(); %#ok<NASGU>

if isfield(smaux, "queueBoundEngine") && isa(smaux.queueBoundEngine, "measurementEngine") ...
        && isvalid(smaux.queueBoundEngine) && smaux.queueBoundEngine == engine ...
        && listenersAreValid(smaux)
    return;
end
deleteListeners(smaux);
smaux.queueBoundEngine = engine;
smaux.queueEngineListeners = { ...
    addlistener(engine, "activeRunMode", "PostSet", @engineStateChanged), ...
    addlistener(engine, "activeRunPhase", "PostSet", @engineStateChanged)};
end

function engineStateChanged(~, ~)
global engine
try
    if isempty(engine) || ~isa(engine, "measurementEngine") || ~isvalid(engine)
        return;
    end
    if engine.activeRunMode == "turbo" && engine.activeRunPhase == "finalizing"
        smQueueState.get().setFinalizing();
    end
    smQueueRefresh();
catch ME
    experimentContext.print("Queue state refresh warning: %s", ME.message);
end
end

function valid = listenersAreValid(smaux)
valid = isfield(smaux, "queueEngineListeners") && iscell(smaux.queueEngineListeners) ...
    && numel(smaux.queueEngineListeners) == 2;
if valid
    for index = 1:numel(smaux.queueEngineListeners)
        listener = smaux.queueEngineListeners{index};
        valid = valid && ~isempty(listener) && isvalid(listener);
    end
end
end

function deleteListeners(smaux)
if ~isfield(smaux, "queueEngineListeners") || ~iscell(smaux.queueEngineListeners)
    return;
end
for index = 1:numel(smaux.queueEngineListeners)
    listener = smaux.queueEngineListeners{index};
    if ~isempty(listener) && isvalid(listener)
        delete(listener);
    end
end
end
