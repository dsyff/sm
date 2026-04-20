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
        out = engine.evalOnEngine(codeString);
    end
else
    if nargout == 0
        evalin("base", char(codeString));
    else
        out = evalin("base", char(codeString));
    end
end
end

