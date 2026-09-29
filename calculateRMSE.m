function metrics = calculateRMSE(y_exp, y_sim, signalName, unitName, alignOffset)
% CALCULATERMSE Computes Root Mean Square Error, Mean Absolute Error, Peak Error,
% and Pearson correlation between experimental and simulated kinematic data.
%
% Inputs:
%   y_exp       : Experimental data vector
%   y_sim       : Simulated data vector (evaluated at matching time points)
%   signalName  : Descriptive name of the channel / sensor
%   unitName    : Measurement units (e.g., 'deg/s', 'deg', 'RPM')
%   alignOffset : Boolean (true/false) whether to align DC offset (default: true)
%
% Output:
%   metrics     : Struct containing computed error and correlation metrics

    if nargin < 3 || isempty(signalName)
        signalName = 'Signal';
    end
    if nargin < 4 || isempty(unitName)
        unitName = 'deg/s';
    end
    if nargin < 5 || isempty(alignOffset)
        alignOffset = true;
    end

    y_e = double(y_exp(:));
    y_s = double(y_sim(:));

    valid = ~isnan(y_e) & ~isnan(y_s);
    y_e = y_e(valid);
    y_s = y_s(valid);

    % Raw RMSE before offset alignment
    rawResiduals = y_e - y_s;
    rawRMSE = sqrt(mean(rawResiduals.^2));

    % Check optimal polarity using Pearson correlation
    R_direct = computePearsonCorr(y_e, y_s);
    R_invert = computePearsonCorr(-y_e, y_s);
    if R_invert > R_direct + 0.1
        y_e_comp = -y_e;
        polarityNote = ' [Inverted]';
    else
        y_e_comp = y_e;
        polarityNote = '';
    end

    % Offset alignment (removes static sensor mounting angle / DC bias)
    if alignOffset
        dc_offset = mean(y_e_comp) - mean(y_s);
        y_s_aligned = y_s + dc_offset;
    else
        dc_offset = 0;
        y_s_aligned = y_s;
    end

    residuals = y_e_comp - y_s_aligned;
    rmse = sqrt(mean(residuals.^2));
    mae = mean(abs(residuals));
    peakErr = max(abs(residuals));
    R_val = computePearsonCorr(y_e_comp, y_s_aligned);

    % If velocity in deg/s, also compute RPM equivalent
    if contains(lower(unitName), 'deg/s') || contains(lower(unitName), 'deg_s')
        rmse_rpm = rmse / 6.0;
    else
        rmse_rpm = NaN;
    end

    metrics.SignalName    = string([char(signalName) polarityNote]);
    metrics.Unit          = string(unitName);
    metrics.RMSE          = round(rmse, 2);
    metrics.Raw_RMSE      = round(rawRMSE, 2);
    metrics.DC_Offset     = round(dc_offset, 2);
    metrics.MAE           = round(mae, 2);
    metrics.PeakError     = round(peakErr, 2);
    metrics.Correlation_R = round(R_val, 4);
    metrics.RMSE_RPM      = round(rmse_rpm, 2);
    metrics.residuals     = residuals;
    metrics.y_sim_aligned = y_s_aligned;
    metrics.y_exp_used    = y_e_comp;
end

function r = computePearsonCorr(x, y)
    x = double(x(:)) - mean(double(x(:)));
    y = double(y(:)) - mean(double(y(:)));
    denom = sqrt(sum(x.^2) * sum(y.^2));
    if denom == 0
        r = 0;
    else
        r = sum(x .* y) / denom;
    end
end
