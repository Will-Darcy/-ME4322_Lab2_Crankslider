function importantChannels = screenSensorColumns(filename)
% SCREENSENSORCOLUMNS Inspects an Excel file to find the most active/oscillating columns.
% Inputs:
%   filename : Path to the .xlsx file
% Outputs:
%   report   : Table sorted by highest dynamic deviation (StdDev)

% 1. Read table preserving headers
tbl = readtable(filename, 'VariableNamingRule', 'preserve');
colNames = tbl.Properties.VariableNames;

% 2. Columns to ignore from dynamic kinematic screening
ignorePatterns = {'time', 'chip_time', 'equipment', 'hall', 'rpm', ...
    'encoderangularvelocity'};

results = struct('Column', {}, 'StdDev', {}, 'PeakToPeak_Range', {}, ...
    'Mean', {}, 'Min', {}, 'Max', {}, 'Status', {});

count = 0;
for i = 1:length(colNames)
    cName = colNames{i};
    lowerName = lower(cName);

    % Skip timestamps, IDs, and constants
    if any(contains(lowerName, ignorePatterns))
        continue;
    end

    colData = tbl.(cName);

    % Ensure column is numeric
    if isnumeric(colData)
        % Drop NaNs if any
        cleanData = colData(~isnan(colData));
        if length(cleanData) < 5
            continue;
        end

        count = count + 1;
        stdVal   = std(cleanData);
        minVal   = min(cleanData);
        maxVal   = max(cleanData);
        rangeVal = maxVal - minVal;
        meanVal  = mean(cleanData);

        % Classify activity level based on dynamic oscillation
        isAngular = contains(lowerName, {'gyro', 'angvel', 'omega'});
        if stdVal > 15 || rangeVal > 40 || (isAngular && (stdVal > 0.15 || rangeVal > 0.4))
            status = "HIGH ACTIVITY (Primary)";
        elseif stdVal > 2 || rangeVal > 5 || (isAngular && (stdVal > 0.05 || rangeVal > 0.1))
            status = "MODERATE";
        else
            status = "LOW / NEAR-ZERO (Negligible)";
        end

        results(count).Column           = string(cName);
        results(count).StdDev           = round(stdVal, 2);
        results(count).PeakToPeak_Range = round(rangeVal, 2);
        results(count).Mean             = round(meanVal, 2);
        results(count).Min              = round(minVal, 2);
        results(count).Max              = round(maxVal, 2);
        results(count).Status           = status;
    end
end

% Convert to table and sort by highest standard deviation
report = struct2table(results);
report = sortrows(report, 'StdDev', 'descend');

% Print formatted overview to Command Window
fprintf('\n========================================================================================\n');
fprintf(' DYNAMIC COLUMN SCREENING REPORT: %s\n', filename);
fprintf('========================================================================================\n');
disp(report(:, {'Column', 'StdDev', 'PeakToPeak_Range', 'Mean', 'Status'}));
fprintf('========================================================================================\n\n');

% Extract the channels list (Assignment Requirements)
% Return string array of important fields to track
importantChannels = ["Slider Distance [mm]", "Gyro Z [deg/s]"];

end

