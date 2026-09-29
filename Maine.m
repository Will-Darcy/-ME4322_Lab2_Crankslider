%% MAINE.M: AUTOMATED PMKS+ KINEMATICS VS. EXPERIMENTAL CRANK-SLIDER DATA COMPARISON
%
% This script automates:
% 1. Universal input loading: accepts raw (.csv, .txt, .mat, or .xlsx)
%    and automatically organizes WitMotion data into separate sensor files.
% 2. Automated steady-state detection and phase alignment with positive acceleration
%    so experimental data and PMKS+ simulations start at the exact same physical state.
% 3. Correcting the PMKS physical time vector and looping/duplicating 1-rev PMKS data
%    across the full duration of experimental revolutions.
% 4. Coupler angular velocity comparison and Slider position comparison.
% 5. Metric calculation: RMSE (deg/s, RPM, and mm), MAE, Peak Error, and Pearson correlation R.
% 6. Formatted summary reporting and export to Excel.
% 7. Overlaid kinematic comparison and residual error plotting.

clearvars;
close all;
clc;

fprintf('========================================================================================\n');
fprintf('  STARTING PMKS+ VS. EXPERIMENTAL CRANK-SLIDER KINEMATIC ANALYSIS & RMSE CALCULATIONS\n');
fprintf('========================================================================================\n\n');

%% 1. Screen and User Verification
fprintf('========================================================================================\n');

file1 = input('---Enter Experimental data file (.csv / data.mat / .xlsx)---: ', 's');

fprintf('========================================================================================\n\n');

if isempty(file1) || ~exist(file1, 'file')
    error('The specified data file was not found: %s', file1);
end
fprintf('Verified input file: %s\n', file1);

% Information about Data Steady State
fprintf('========================================================================================\n\n');

ministart = input('--- After perliminary analysis please enter a time (sec) where data is steady state---: ');

% Validate the requested steady-state start time before continuing
if ~isscalar(ministart) || ~isfinite(ministart) || ministart < 0
    error('Steady-state start time must be a finite, nonnegative scalar.');
end

fprintf('Steady-state analysis will begin at %.3f s.\n', ministart);

% Screen columns to detect active sensor channels
rep1 = screenSensorColumns(file1);

%% 2. Data Extraction
fprintf('\n--- 2. Extracting Experimental Sensor Data ---\n');

% Extract channels using screening report
[S.time, S.data, S.names] = extractSensorData(file1, rep1);

% Also load raw table for full access
s1_raw = readtable(file1, 'VariableNamingRule', 'preserve');

fprintf('  Extracted Sensor Data: %d samples across %d active channels\n', length(S.time), length(S.names));


%% 3. Load PMKS+ Kinematic Loop Simulation Data
fprintf('\n--- 3. Operating RPM Calculation & PMKS File Requirement Analysis ---\n');

[RPM1, RPM2, Tslider, Tgyro] = calculateLinkagePeriod(file1, ministart);

% Operating speed grouping tolerance (0.75 RPM or ~4% tolerance)
rpmTol = 0.75;
match_1_2 = abs(RPM1 - RPM2) <= rpmTol;

% Sensors data should match at one speed (Standard)
rpm  = mean([RPM1, RPM2]);

fprintf('========================================================================================\n');
fprintf('  PMKS REQUIREMENT: PMKS SIMULATION FILE NEEDED\n');
fprintf('  Distinct operating speeds detected:\n');
fprintf('    1. Sensors (Input Crank): ~%.2f RPM\n', rpm);
fprintf('========================================================================================\n\n');

fprintf('Do you have the PMKS simulation file(s) for these RPM values ready?\n');
havePMKS = input('Proceed with PMKS kinematic comparison now? [Y/N]: ', 's');

if ~ismember(upper(strtrim(havePMKS)), {'Y', 'YES'})
    fprintf('\n========================================================================================\n');
    fprintf('  PMKS SIMULATION SETUP GUIDE (Run these simulations in PMKS+):\n');
    fprintf('========================================================================================\n');
    fprintf('  To complete kinematic comparison and RMSE calculations:\n');
    fprintf('  1. Open PMKS+ and configure your 4-bar linkage dimensions.\n');
    fprintf('  2. Set Crank Motor Speed to: %.2f RPM\n', rpm);
    fprintf('  3. Export kinematics Excel spreadsheet.\n');

    fprintf('  4. Re-run Maine.m and enter the exported PMKS file(s) when prompted.\n');
    fprintf('========================================================================================\n');
    fprintf('  Sensor data extraction, organization, and RPM calculation completed successfully!\n');
    fprintf('========================================================================================\n');
    return;

end

promptPMKS = sprintf('---Enter PMKS file for %.2f RPM---: ', rpm);
pmks_file1 = input(promptPMKS, 's');
if ~exist(pmks_file1, 'file')
    error('PMKS file not found: %s', pmks_file1);
end
pmksfile = readtable(pmks_file1, 'VariableNamingRule', 'preserve');

file2 = pmksfile;
% User confirmed PMKS files are ready: prompt and load tables
fprintf('\n--- 3. Loading PMKS+ Kinematic Simulation Files ---\n');


fprintf('  Loaded File 2: (%.2f RPM simulation, %d rows)\n', rpm, height(file2));


%% 4. Process Dataset: RPM Experimental Crank-Slider Test
fprintf('\n========================================================================================\n');
fprintf('  PROCESSING DATASET: RPM EXPERIMENTAL CRANK-SLIDER TEST\n');
fprintf('========================================================================================\n');

% Extract primary signals from Data file 1
time_start = s1_raw.('Time [ms]')(1);
t_daq = double(s1_raw.('Time [ms]') - time_start) / 1000.0; % Convert ms to seconds
[t_daq, u_daq] = unique(t_daq, 'stable');

% Gyro Z: Raw values recorded in rad/s, convert to deg/s for standardized kinematic analysis
bno_gyro_z_rad  = double(s1_raw.('Gyro Z [deg/s]')(u_daq));
bno_vel_z_deg_s = bno_gyro_z_rad * (180.0 / pi);

% Slider Distance: Recorded in mm
bno_Slid_D_mm   = double(s1_raw.('Slider Distance [mm]')(u_daq));

% Align steady-state starting point matching PMKS initial state with positive acceleration
[tStart_daq, idxKeep_daq, tAligned_daq, numRevs] = ...
    findSteadyStateAndAlign(t_daq, bno_vel_z_deg_s, file2, rpm, 1.5);

% Trim all companion DAQ sensor channels to the common steady-state window
t_daq_ss      = tAligned_daq;
bno_vel_z_ss  = bno_vel_z_deg_s(idxKeep_daq);
bno_Slid_D_ss = bno_Slid_D_mm(idxKeep_daq);

% Duplicate / loop the 1-rev PMKS kinematics over the needed duration
[pmks14_rep, T_14, t_sim14] = repeatPMKSData(file2, rpm, numRevs + 1);

% Resample continuous PMKS kinematics onto experimental timestamps
% 1. Coupler angular velocity (Link CB): convert rad/s to deg/s
sim_cb_deg_s = pmks14_rep.('Link CB angVel rad/s') * (180.0 / pi);
pmks14_angle_vel = interp1(t_sim14, sim_cb_deg_s, t_daq_ss, 'pchip', 'extrap');

% 2. Slider position (Joint C): convert cm to mm
sim_slider_mm = pmks14_rep.('Joint C x cm') * 10.0;
pmks14_slider = interp1(t_sim14, sim_slider_mm, t_daq_ss, 'pchip', 'extrap');

% Calculate RMSE metrics for Dataset
daqResults.t          = t_daq_ss;
daqResults.BNO_w_exp  = bno_vel_z_ss;
daqResults.BNO_w_sim  = pmks14_angle_vel;
daqResults.m_BNO_w    = calculateRMSE(bno_vel_z_ss, pmks14_angle_vel, 'Coupler \omega (Link CB)', 'deg/s', true);

daqResults.BNO_s_exp  = bno_Slid_D_ss;
daqResults.BNO_s_sim  = pmks14_slider;
daqResults.m_BNO_s    = calculateRMSE(bno_Slid_D_ss, pmks14_slider, 'Slider Position (Joint C)', 'mm', true);


%% 5. Formatted Summary Error Tables
fprintf('\n========================================================================================\n');
fprintf('  FINAL KINEMATIC ACCURACY & RMSE SUMMARY REPORT\n');
fprintf('========================================================================================\n\n');

mList1 = {daqResults.m_BNO_w, daqResults.m_BNO_s};
table1_data = struct('Channel', {}, 'Unit', {}, 'RMSE', {}, 'RMSE_RPM', {}, 'MAE', {}, 'PeakError', {}, 'DC_Offset', {}, 'Correlation_R', {});
for i = 1:length(mList1)
    m = mList1{i};
    table1_data(i).Channel       = m.SignalName;
    table1_data(i).Unit          = m.Unit;
    table1_data(i).RMSE          = m.RMSE;
    table1_data(i).RMSE_RPM      = m.RMSE_RPM;
    table1_data(i).MAE           = m.MAE;
    table1_data(i).PeakError     = m.PeakError;
    table1_data(i).DC_Offset     = m.DC_Offset;
    table1_data(i).Correlation_R = m.Correlation_R;
end
tSummary1 = struct2table(table1_data);
fprintf('--- DATASET: %.2f RPM CRANK-SLIDER SENSOR RUN ---\n', rpm);
disp(tSummary1);

% Save summary table to Excel
summaryFile = sprintf('RMSE_Summary_%.2fRPM_CrankSlider.xlsx', rpm);
try
    writetable(tSummary1, summaryFile);
    fprintf('  Saved Excel summary table: %s\n', summaryFile);
catch ME
    warning('Could not overwrite %s (%s). File may be open in Excel.', summaryFile, ME.message);
end


%% 6. Generate Overlaid Comparison Graphs
fprintf('\n--- 6. Generating Comparison Graphs and Saving Figures ---\n');

% Colors
c_blue   = [0.00, 0.45, 0.74];
c_red    = [0.85, 0.15, 0.15];
c_green  = [0.10, 0.60, 0.20];
c_purple = [0.49, 0.18, 0.56];

f = figure('Name', sprintf('%.2f RPM Crank Slider Kinematic Comparison', rpm), 'Color', 'w', 'Position', [100, 100, 1150, 750]);
tiled = tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
mainTitle = title(tiled, sprintf('%.2f RPM Crank-Slider: Experimental Data vs. Looped PMKS+ Kinematics (%.4f Revolutions)', rpm, numRevs), ...
    'FontSize', 14, 'FontWeight', 'bold', 'Color', [0.1 0.1 0.1]);

% Subplot 1: Coupler Angular Velocity Overlay
ax1 = nexttile(tiled, 1);
plot(daqResults.t, daqResults.m_BNO_w.y_exp_used, 'Color', c_blue, 'LineWidth', 1.3); hold on;
plot(daqResults.t, daqResults.m_BNO_w.y_sim_aligned, 'Color', c_red, 'LineStyle', '--', 'LineWidth', 1.5);
grid on;
set(ax1, 'Color', 'w', 'XColor', [0.15 0.15 0.15], 'YColor', [0.15 0.15 0.15]);
xlabel('Aligned Time (s)', 'Color', [0.15 0.15 0.15]);
ylabel('Angular Velocity (deg/s)', 'Color', [0.15 0.15 0.15]);
title(sprintf('Coupler \\omega (RMSE: %.2f deg/s | %.2f RPM | R = %.4f)', ...
    daqResults.m_BNO_w.RMSE, daqResults.m_BNO_w.RMSE_RPM, daqResults.m_BNO_w.Correlation_R), ...
    'FontWeight', 'bold', 'Color', [0.1 0.1 0.1]);
legend('Experimental (Gyro Z)', 'PMKS Simulation', 'Location', 'best');

% Subplot 2: Coupler Angular Velocity Residual Error
ax2 = nexttile(tiled, 2);
plot(daqResults.t, daqResults.m_BNO_w.residuals, 'Color', c_green, 'LineWidth', 1.1); hold on;
yline(0, 'k--', 'LineWidth', 1.0);
grid on;
set(ax2, 'Color', 'w', 'XColor', [0.15 0.15 0.15], 'YColor', [0.15 0.15 0.15]);
xlabel('Aligned Time (s)', 'Color', [0.15 0.15 0.15]);
ylabel('Residual Error (deg/s)', 'Color', [0.15 0.15 0.15]);
title(sprintf('Coupler \\omega Residuals (MAE: %.2f deg/s | Peak: %.2f deg/s)', ...
    daqResults.m_BNO_w.MAE, daqResults.m_BNO_w.PeakError), ...
    'FontWeight', 'bold', 'Color', [0.1 0.1 0.1]);

% Subplot 3: Slider Position Overlay
ax3 = nexttile(tiled, 3);
plot(daqResults.t, daqResults.m_BNO_s.y_exp_used, 'Color', c_blue, 'LineWidth', 1.3); hold on;
plot(daqResults.t, daqResults.m_BNO_s.y_sim_aligned, 'Color', c_red, 'LineStyle', '--', 'LineWidth', 1.5);
grid on;
set(ax3, 'Color', 'w', 'XColor', [0.15 0.15 0.15], 'YColor', [0.15 0.15 0.15]);
xlabel('Aligned Time (s)', 'Color', [0.15 0.15 0.15]);
ylabel('Slider Position (mm)', 'Color', [0.15 0.15 0.15]);
title(sprintf('Slider Position (RMSE: %.2f mm | R = %.4f)', ...
    daqResults.m_BNO_s.RMSE, daqResults.m_BNO_s.Correlation_R), ...
    'FontWeight', 'bold', 'Color', [0.1 0.1 0.1]);
legend('Experimental (Distance)', 'PMKS Simulation (Joint C)', 'Location', 'best');

% Subplot 4: Slider Position Residual Error
ax4 = nexttile(tiled, 4);
plot(daqResults.t, daqResults.m_BNO_s.residuals, 'Color', c_purple, 'LineWidth', 1.1); hold on;
yline(0, 'k--', 'LineWidth', 1.0);
grid on;
set(ax4, 'Color', 'w', 'XColor', [0.15 0.15 0.15], 'YColor', [0.15 0.15 0.15]);
xlabel('Aligned Time (s)', 'Color', [0.15 0.15 0.15]);
ylabel('Residual Error (mm)', 'Color', [0.15 0.15 0.15]);
title(sprintf('Slider Position Residuals (MAE: %.2f mm | Peak: %.2f mm)', ...
    daqResults.m_BNO_s.MAE, daqResults.m_BNO_s.PeakError), ...
    'FontWeight', 'bold', 'Color', [0.1 0.1 0.1]);

% Save Figure
plotFile = sprintf('Comparison_%.2fRPM_CrankSlider.png', rpm);
saveas(f, plotFile);
fprintf('  Saved kinematic comparison figure: %s\n', plotFile);

fprintf('\n========================================================================================\n');
fprintf('  ANALYSIS AND AUTOMATION COMPLETE!\n');
fprintf('========================================================================================\n');