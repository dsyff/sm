classdef instrument_toyBLG < instrumentInterface
    % instrument_toyBLG (minimal)
    %
    % Dual-gated BLG map model, B=0, dual-gate region only.
    %
    % Gate mapping:
    %   n = (C_tg*V_tg + C_bg*V_bg)/e + n0
    %   D = 0.5*(eps_tg*V_tg/h_tg - eps_bg*V_bg/h_bg) + D0   (in V/nm)
    %
    % Minimal resistance model (only smoothing is n_rms):
    %   Rxx(n,D) = R_metal(n) + R_gap(D)*exp(-0.5*(n/n_rms)^2)
    %
    % where:
    %   R_metal(n) = (L/W) / ( sigma0 + e*mu*sqrt(n^2 + n_rms^2) )
    %   R_gap(D)   = Rgap0_ohm * 10^( log10Rgap_per_V_per_nm * |D| )
    %
    % Notes:
    %   - n_rms is the ONLY broadening knob (sets peak width, and removes |n| cusp).
    %   - D dependence is tuned directly by log10Rgap_per_V_per_nm (decades per V/nm).
    %   - No extra smoothing (no n_floor, no nSmooth, no EMT, no enforceTargetRatio).

    % -------------------------
    % Internal state (channels)
    % -------------------------
    properties (Access = private)
        vBg (1,1) double = 0;        % bottom-gate voltage [V]
        vTg (1,1) double = 0;        % top-gate voltage [V]

        % Default: dual hBN, 20 nm each
        hBg (1,1) double = 20e-9;    % bottom dielectric thickness [m]
        hTg (1,1) double = 20e-9;    % top dielectric thickness [m]

        n0  (1,1) double = 0;        % density offset [1/m^2]
        D0_V_per_nm (1,1) double = 0;     % displacement-field offset [V/nm]
    end

    % -------------------------
    % Constants
    % -------------------------
    properties (Access = private)
        eps0    (1,1) double = 8.8541878128e-12;   % vacuum permittivity [F/m]
        eCharge (1,1) double = 1.602176634e-19;    % elementary charge [C]
    end

    % -------------------------
    % Tunable parameters (minimal)
    % -------------------------
    properties
        % Dielectrics (hBN out-of-plane ~3-4)
        eps_bg (1,1) double = 3.4;   % relative permittivity bottom dielectric
        eps_tg (1,1) double = 3.4;   % relative permittivity top dielectric

        % Geometry (only L/W matters)
        L (1,1) double = 1.0;        % length [m]
        W (1,1) double = 1.0;        % width  [m]

        % Broadening / inhomogeneity (ONLY smoothing knob)
        n_rms (1,1) double = 1e16;   % [1/m^2] ~ 3e10 cm^-2

        % Metallic background channel
        mu_mob (1,1) double = 0.5;   % mobility [m^2/(V*s)]
        sigma0 (1,1) double = 2e-4;  % residual conductivity [S] (sets far-tail floor)

        % D-dependent gap ridge amplitude
        Rgap0_ohm (1,1) double = 1e3;     % peak ridge amplitude at D=0 [Ohm]
        log10Rgap_per_V_per_nm (1,1) double = 1.5; % decades per V/nm (2.5 -> 1e5 at 2 V/nm)

        % Safety clamp to prevent overflow if you crank D too hard (not a "smoothing" knob)
        max_decades (1,1) double = 12;    % cap on log10 gain
    end

    % -------------------------
    % Constructor
    % -------------------------
    methods
        function obj = instrument_toyBLG(address, NameValueArgs)
            arguments
                address (1,1) string {mustBeNonzeroLengthText};
                NameValueArgs.h_bg   (1,1) double {mustBePositive, mustBeFinite} = 20e-9;
                NameValueArgs.h_tg   (1,1) double {mustBePositive, mustBeFinite} = 20e-9;
                NameValueArgs.n0     (1,1) double {mustBeFinite} = 0;
                NameValueArgs.D0_V_per_nm (1,1) double {mustBeFinite} = 0;
            end

            obj@instrumentInterface();
            obj.address = address;

            obj.hBg = NameValueArgs.h_bg;
            obj.hTg = NameValueArgs.h_tg;
            obj.n0  = NameValueArgs.n0;
            obj.D0_V_per_nm = NameValueArgs.D0_V_per_nm;

            % Channels (order matters for channel indices)
            obj.addChannel("h_bg");         % 1
            obj.addChannel("h_tg");         % 2
            obj.addChannel("n0");           % 3
            obj.addChannel("D0_V_per_nm");  % 4
            obj.addChannel("V_bg");         % 5
            obj.addChannel("V_tg");         % 6
            obj.addChannel("Rxx");          % 7 (read-only)
        end
    end

    % -------------------------
    % Instrument interface
    % -------------------------
    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(~, ~)
            % Virtual instrument: no write-back needed.
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            value = setValues(1);
            if ~isfinite(value)
                error("instrument_toyBLG:NonFiniteInput", "Channel value must be finite.");
            end

            switch channelIndex
                case 1 % h_bg
                    if value <= 0, error("instrument_toyBLG:InvalidThickness", "h_bg must be positive."); end
                    obj.hBg = value;
                case 2 % h_tg
                    if value <= 0, error("instrument_toyBLG:InvalidThickness", "h_tg must be positive."); end
                    obj.hTg = value;
                case 3 % n0
                    obj.n0 = value;
                case 4 % D0_V_per_nm
                    obj.D0_V_per_nm = value;
                case 5 % V_bg
                    obj.vBg = value;
                case 6 % V_tg
                    obj.vTg = value;
                case 7 % Rxx
                    error("instrument_toyBLG:ReadOnlyChannel", "Rxx is read-only.");
                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            switch channelIndex
                case 1
                    getValues = obj.hBg;
                case 2
                    getValues = obj.hTg;
                case 3
                    getValues = obj.n0;
                case 4
                    getValues = obj.D0_V_per_nm;
                case 5
                    getValues = obj.vBg;
                case 6
                    getValues = obj.vTg;
                case 7
                    getValues = obj.computeRxx();
                otherwise
                    error("instrument_toyBLG:UnsupportedChannel", "Unsupported channel index %d.", channelIndex);
            end
        end
    end

    % -------------------------
    % Core model
    % -------------------------
    methods (Access = private)
        function Rxx = computeRxx(obj)
            if obj.n_rms <= 0
                error("instrument_toyBLG:InvalidNRMS", "n_rms must be > 0.");
            end
            if obj.mu_mob < 0 || obj.sigma0 < 0
                error("instrument_toyBLG:InvalidMetalParams", "mu_mob and sigma0 must be >= 0.");
            end

            % Gate capacitances per unit area [F/m^2]
            C_tg = obj.eps0 * obj.eps_tg / obj.hTg;
            C_bg = obj.eps0 * obj.eps_bg / obj.hBg;

            % Density [1/m^2]
            n = (C_tg * obj.vTg + C_bg * obj.vBg) / obj.eCharge + obj.n0;

            % Displacement field proxy [V/nm]
            D_V_per_nm = 1e-9 * 0.5 * ( (obj.eps_tg * obj.vTg / obj.hTg) - (obj.eps_bg * obj.vBg / obj.hBg) ) + obj.D0_V_per_nm;
            Dabs = abs(D_V_per_nm);

            % Metallic background: smooth even function of n using n_rms as the only regularizer
            sigma_metal = obj.sigma0 + obj.eCharge * obj.mu_mob * sqrt(n.^2 + obj.n_rms.^2);
            R_metal = (obj.L / obj.W) / max(sigma_metal, realmin);

            % D-dependent ridge amplitude (direct knob)
            decades = obj.log10Rgap_per_V_per_nm * Dabs;
            decades = min(decades, obj.max_decades);
            Rgap0 = obj.Rgap0_ohm * (10.^decades);

            % Single smooth peak vs n (width set ONLY by n_rms)
            R_gap = Rgap0 * exp(-0.5 * (n ./ obj.n_rms).^2);

            Rxx = R_metal + R_gap;
        end
    end
end
