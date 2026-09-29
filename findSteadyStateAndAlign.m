function [tStart, idxKeep, tAligned, numRevs] = findSteadyStateAndAlign(t_exp, vel_exp, pmks_table, targetRPM, minStartTime)
% FINDSTEADYSTATEANDALIGN Identifies the steady-state starting point where the
% physical mechanism state matches PMKS t=0 with positive acceleration, then
% synchronizes and trims experimental timestamps.
%
% Inputs:
%   t_exp        : Experimental time vector in seconds
%   vel_exp      : Experimental angular velocity signal for alignment (e.g., Follower Gyro)
%   pmks_table   : Single-cycle PMKS table
%   targetRPM    : Operating speed in RPM (15.0 or 16.17)
%   minStartTime : Minimum time to consider for steady state (default: 1.5s)
%
% Outputs:
%   tStart   : Selected experimental timestamp corresponding to PMKS t=0
%   idxKeep  : Logical mask of experimental samples to keep
%   tAligned : Time vector starting at 0 for the trimmed interval
%   numRevs  : Number of full revolutions spanned in the trimmed data

    if nargin < 5 || isempty(minStartTime)
        minStartTime = 1.5;
    end

    T_period = 60.0 / double(targetRPM);

    % 1. Find the positive zero-crossing landmark in 1-cycle PMKS Follower / Coupler
    nUnique = height(pmks_table) - 1;
    dt_sim = T_period / double(nUnique);
    t_sim = (0 : (nUnique - 1))' * dt_sim;
    
    if ismember('Link CB angVel rad/s', pmks_table.Properties.VariableNames)
        w_sim = pmks_table.('Link CB angVel rad/s')(1:nUnique);
    elseif ismember('Link DCE angVel rad/s', pmks_table.Properties.VariableNames)
        w_sim = pmks_table.('Link DCE angVel rad/s')(1:nUnique) * (180.0 / pi);
    else
        % Pick the column with greatest oscillation deviation
        cNames = pmks_table.Properties.VariableNames;
        bestCol = cNames{end};
        maxStd = 0;
        for ci = 1:length(cNames)
            cdat = pmks_table.(cNames{ci});
            if isnumeric(cdat) && std(cdat) > maxStd
                maxStd = std(cdat);
                bestCol = cNames{ci};
            end
        end
        w_sim = pmks_table.(bestCol)(1:nUnique);
    end

    % Remove DC offset for zero-crossing detection if needed
    w_sim_centered = w_sim - mean(w_sim);

    t_zero_sim = NaN;
    for k = 2:length(w_sim_centered)
        if w_sim_centered(k-1) <= 0 && w_sim_centered(k) > 0
            frac = -w_sim_centered(k-1) / (w_sim_centered(k) - w_sim_centered(k-1));
            t_zero_sim = t_sim(k-1) + frac * (t_sim(k) - t_sim(k-1));
            break;
        end
    end
    if isnan(t_zero_sim)
        t_zero_sim = 0; % fallback
    end

    % 2. Smooth experimental velocity slightly to avoid noise-induced false zero crossings
    v_clean = fillmissing(double(vel_exp), 'linear');
    v_centered = v_clean - mean(v_clean); % Center signal around zero
    if length(v_centered) > 15
        v_smooth = smoothdata(v_centered, 'gaussian', 9);
    else
        v_smooth = v_centered;
    end

    % 3. Locate positive zero crossings in experimental data in steady state
    crossings = [];
    for k = 2:length(v_smooth)
        if t_exp(k) >= minStartTime
            if v_smooth(k-1) <= 0 && v_smooth(k) > 0
                frac = -v_smooth(k-1) / (v_smooth(k) - v_smooth(k-1));
                t_cross = t_exp(k-1) + frac * (t_exp(k) - t_exp(k-1));
                crossings = [crossings; t_cross]; %#ok<AGROW>
            end
        end
    end

    if isempty(crossings)
        warning('No positive zero crossing detected after minStartTime = %.1fs. Defaulting to minStartTime.', minStartTime);
        tStart = minStartTime;
    else
        % Pick the first reliable positive zero-crossing
        % Cycle start corresponding to PMKS t=0 is (t_cross - t_zero_sim)
        candidateStart = crossings(1) - t_zero_sim;
        if candidateStart < t_exp(1) && length(crossings) > 1
            candidateStart = crossings(2) - t_zero_sim;
        end
        tStart = max(t_exp(1), candidateStart);
    end

    % 4. Create logical mask and aligned time
    idxKeep = (t_exp >= tStart);
    tAligned = t_exp(idxKeep) - tStart;

    % 5. Count full revolutions available
    maxTime = max(tAligned);
    numRevs = max(1, floor(maxTime / T_period));
    
    fprintf('  Steady-state cycle start: t = %.3f s | Span: %.2f s (%.1f revs of T = %.3f s)\n', ...
        tStart, maxTime, maxTime / T_period, T_period);
end
