function [RPM1, RPM2, Tslider, Tgyro] = calculateLinkagePeriod(file1, minStartTimeSec)
% CALCULATELINKAGEPERIOD Estimate crank-slider period and RPM from sensor data.
%
% Inputs:
%   s1_tbl           - file path or table containing the data
%   minStartTimeSec  - optional steady-state start time in seconds (default = 0)
%
% Outputs:
%   rpmSlider        - RPM from slider position peaks
%   rpmGyro          - RPM from gyro peaks
%   Tslider          - period from slider peaks (s)
%   Tgyro            - period from gyro peaks (s)

if nargin < 2 || isempty(minStartTimeSec)
    minStartTimeSec = 0;
end

s1_tbl = file1;
if isempty(s1_tbl)
    error('Input data cannot be empty.');
end


if ischar(s1_tbl) || isstring(s1_tbl)
    s1_tbl = readtable(s1_tbl, 'VariableNamingRule', 'preserve');
end

% Time vector in seconds
time_start = s1_tbl.('Time [ms]')(1);
t1 = (double(s1_tbl.('Time [ms]')) - double(time_start)) / 1000;

% Keep only steady-state data if requested
valid = isfinite(t1) & (t1 >= minStartTimeSec);
t1 = t1(valid);

SL1 = double(s1_tbl.('Slider Distance [mm]'));
GZ1 = double(s1_tbl.('Gyro Z [deg/s]'));

SL1 = SL1(valid);
GZ1 = GZ1(valid);

% Slider peaks
[~, locs1_S] = findpeaks(SL1, t1, 'MinPeakDistance', 1, 'MinPeakProminence', 50);
if numel(locs1_S) >= 2
    Tslider = mean(diff(locs1_S));
    freqSlider = 1 / Tslider;
    rpmSlider = freqSlider * 60;
else
    Tslider = NaN;
    rpmSlider = NaN;
end

% Gyro peaks
[~, locs1_G] = findpeaks(GZ1, t1, 'MinPeakDistance', 1, 'MinPeakProminence', 0.4);
if numel(locs1_G) >= 2
    Tgyro = mean(diff(locs1_G));
    freqGyro = 1 / Tgyro;
    rpmGyro = freqGyro * 60;
else
    Tgyro = NaN;
    rpmGyro = NaN;
end

fprintf('================ CRANK SLIDER LINKAGE PERIOD ANALYSIS ================\n');
if ~isnan(rpmSlider)
    fprintf('  Slider Position : Freq = %.4f Hz | T = %.3f s | RPM = %.2f\n', 1/Tslider, Tslider, rpmSlider);
end
if ~isnan(rpmGyro)
    fprintf('  Coupler Gyro Z  : Freq = %.4f Hz | T = %.3f s | RPM = %.2f\n', 1/Tgyro, Tgyro, rpmGyro);
end
RPM1 = rpmSlider;
RPM2 = rpmGyro;
end