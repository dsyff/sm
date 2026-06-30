function out = smeval(codeString)
%SMEVAL Evaluate code on the measurement engine worker when available.

arguments
    codeString {mustBeTextScalar}
end

codeString = string(codeString);
out = [];

global engine %#ok<GVMIS>
if exist("engine", "var") && ~isempty(engine) && isa(engine, "measurementEngine")
    if nargout == 0
        engine.evalOnEngine(codeString);
    else
        out = engine.evalOnEngine(codeString, outputMode = "display");
    end
else
    if nargout == 0
        evalin("base", char(codeString));
    else
        out = evalin("base", char(codeString));
        try
            out = string(formattedDisplayText(out));
        catch ME
            error("smeval:EvalOutputDisplayFailed", ...
                "Failed to format eval output for display (%s): %s", class(out), ME.message);
        end
    end
end
end

