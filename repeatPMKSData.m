function [repTable, T_period, t_phys] = repeatPMKSData(pmksTable, targetRPM, numRevs)
% REPEATPMKSDATA Corrects the PMKS physical time base and duplicates/loops 
% 1-revolution PMKS kinematic data across multiple continuous revolutions.
%
% Inputs:
%   pmksTable : MATLAB table loaded from PMKS+ kinematic loop Excel file
%   targetRPM : Operating speed in RPM (e.g., 15.0 or 16.17)
%   numRevs   : Number of complete cycles/revolutions to generate (default: 6)
%
% Outputs:
%   repTable  : MATLAB table with repeated continuous kinematics
%   T_period  : Physical period of one revolution in seconds (60 / targetRPM)
%   t_phys    : Continuous physical time vector (seconds)

    if nargin < 3 || isempty(numRevs)
        numRevs = 6;
    end
    numRevs = max(1, round(numRevs));

    % 1. Physical Period of 1 Revolution
    T_period = 60.0 / double(targetRPM);

    % 2. Isolate Unique Cycle Data (exclude the duplicate 360°/0° closing point)
    nRows = height(pmksTable);
    if nRows > 1
        nUnique = nRows - 1;
        singleCycle = pmksTable(1:nUnique, :);
    else
        nUnique = 1;
        singleCycle = pmksTable;
    end

    dt = T_period / double(nUnique);
    t_single = (0 : (nUnique - 1))' * dt;

    % 3. Extract and Compute Geometry Angles for Single Cycle
    % Check if joint coordinate columns exist
    hasJoints4Bar = ismember('Joint B x cm', pmksTable.Properties.VariableNames) && ...
                    ismember('Joint F x cm', pmksTable.Properties.VariableNames);
    hasJointsCrankSlider = ismember('Joint B x cm', pmksTable.Properties.VariableNames) && ...
                          ismember('Joint C x cm', pmksTable.Properties.VariableNames);

    if hasJoints4Bar
        Bx = singleCycle.('Joint B x cm');
        By = singleCycle.('Joint B y cm');
        Fx = singleCycle.('Joint F x cm');
        Fy = singleCycle.('Joint F y cm');
        Dx = singleCycle.('Joint D x cm');
        Dy = singleCycle.('Joint D y cm');
        Ex = singleCycle.('Joint E x cm');
        Ey = singleCycle.('Joint E y cm');
        Gx = singleCycle.('Joint G x cm');
        Gy = singleCycle.('Joint G y cm');
        Ax = singleCycle.('Joint A x cm');
        Ay = singleCycle.('Joint A y cm');

        % Vector angles using atan2
        singleCycle.angleF_deg = rad2deg(atan2(By - Fy, Bx - Fx)); % Coupler B-F
        singleCycle.angleE_deg = rad2deg(atan2(Dy - Ey, Dx - Ex)); % Follower D-E
        singleCycle.angleG_deg = rad2deg(atan2(By - Gy, Bx - Gx)); % Coupler B-G
        
        % Crank A-B: Continuously unwrap full 360-deg rotation
        crank_ang_rad = atan2(By - Ay, Bx - Ax);
        singleCycle.angleAB_deg = rad2deg(unwrap(crank_ang_rad));
    elseif hasJointsCrankSlider
        Bx = singleCycle.('Joint B x cm');
        By = singleCycle.('Joint B y cm');
        Cx = singleCycle.('Joint C x cm');
        Cy = singleCycle.('Joint C y cm');
        Ax = singleCycle.('Joint A x cm');
        Ay = singleCycle.('Joint A y cm');

        % Coupler Link CB orientation angle
        singleCycle.angleCB_deg = rad2deg(atan2(By - Cy, Bx - Cx));

        % Slider position converted to mm
        singleCycle.('Joint C x mm') = Cx * 10.0;
        singleCycle.Joint_C_x_mm     = Cx * 10.0;

        % Crank A-B: Continuously unwrap full 360-deg rotation
        crank_ang_rad = atan2(By - Ay, Bx - Ax);
        singleCycle.angleAB_deg = rad2deg(unwrap(crank_ang_rad));
    end

    % Convert angular velocities from rad/s to deg/s and RPM
    varNames = singleCycle.Properties.VariableNames;
    angVelCols = varNames(contains(varNames, 'angVel'));
    for k = 1:length(angVelCols)
        cName = angVelCols{k};
        rad_s = singleCycle.(cName);
        deg_s = rad_s * (180.0 / pi);
        rpm_val = deg_s / 6.0;

        baseName = extractBefore(cName, ' angVel');
        if isempty(baseName)
            baseName = cName;
        end
        cleanBase = strrep(strtrim(baseName), ' ', '_');
        singleCycle.([baseName '_angVel_deg_s'])  = deg_s;
        singleCycle.([baseName '_angVel_RPM'])    = rpm_val;
        singleCycle.([cleanBase '_angVel_deg_s']) = deg_s;
        singleCycle.([cleanBase '_angVel_RPM'])   = rpm_val;
    end

    % 4. Duplicate for numRevs
    repeatedCells = cell(numRevs, 1);
    t_all = [];

    for m = 1:numRevs
        cycleTable = singleCycle;
        cycleTime = t_single + (m - 1) * T_period;

        % For rotating angles (Crank / Link AB), unwrap continuously
        if ismember('Link AB angle degree', cycleTable.Properties.VariableNames)
            cycleTable.('Link AB angle degree') = cycleTable.('Link AB angle degree') + (m - 1) * 360.0;
        end
        if ismember('angleAB_deg', cycleTable.Properties.VariableNames)
            cycleTable.angleAB_deg = cycleTable.angleAB_deg + (m - 1) * 360.0;
        end

        repeatedCells{m} = cycleTable;
        t_all = [t_all; cycleTime]; %#ok<AGROW>
    end

    % Append the final closing boundary point
    lastRow = singleCycle(1, :);
    if ismember('Link AB angle degree', lastRow.Properties.VariableNames)
        lastRow.('Link AB angle degree') = lastRow.('Link AB angle degree') + numRevs * 360.0;
    end
    if ismember('angleAB_deg', lastRow.Properties.VariableNames)
        lastRow.angleAB_deg = lastRow.angleAB_deg + numRevs * 360.0;
    end
    t_all = [t_all; numRevs * T_period];

    repTable = vertcat(repeatedCells{:}, lastRow);
    repTable.Time_s = t_all;
    t_phys = t_all;
end
