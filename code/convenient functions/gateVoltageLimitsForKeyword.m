function limits = gateVoltageLimitsForKeyword(keyword, vTgLimits, vBgLimits)
arguments
    keyword (1, 1) string
    vTgLimits (1, 2) double
    vBgLimits (1, 2) double
end

switch keyword
    case "tg"
        limits = vTgLimits;
    case "bg"
        limits = vBgLimits;
    otherwise
        limits = [-10, 10];
end
end
