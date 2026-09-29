function [t_sec, dataMatrix, varNames] = extractSensorData(filename, channels)
    % filename   : path to data file (e.g., 'run_data.csv')
    % channels   : string array or cell array of chars (e.g., ["BMO1GyroX", "BMO1GyroY"] or 'AngleZ')
    
    raw = readtable(filename, 'VariableNamingRule', 'preserve');
    % detect time column name
    colNames = raw.Properties.VariableNames;
    if ismember('Time', colNames)
        t_raw = double(raw.Time);
        t_sec = (t_raw - t_raw(1)) / 1000.0; % Convert ms to seconds and zero-shift
    elseif ismember('Time [ms]', colNames)
        t_raw = double(raw.('Time [ms]'));
        t_sec = (t_raw - t_raw(1)) / 1000.0; % Convert ms to seconds and zero-shift
    elseif ismember('Chip_Time_s', colNames)
        t_raw = double(raw.Chip_Time_s);
        t_sec = t_raw - t_raw(1);
    else
        error("No time column found under names Time, Time [ms], or Chip_Time_s.")
    end
    
    % Build expected variable names: 'sensor1_vel_x', 'sensor1_vel_y', etc.
    targetVars = string(channels);
    
    
    dataRaw = table2array(raw(:, targetVars));
    
    
    [t_sec, uniqueIdx] = unique(t_sec, 'stable');

    % Extract slice and convert directly to a numeric matrix
    dataMatrix = dataRaw(uniqueIdx, :);
    varNames = targetVars;
end