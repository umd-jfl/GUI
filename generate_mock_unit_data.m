%% generate_mock_three_excel_inputs.m
clear; clc;

rootDir = fullfile(pwd, "MockUnitData");

if ~exist(rootDir, "dir")
    mkdir(rootDir);
end

rng(1);

units = ["Unit01", "Unit02", "Unit03"];
pols = ["Hpol", "Vpol"];

freq_2_6  = 2:0.1:6;
freq_6_18 = 6:0.1:18;
freqFull  = (2:0.1:18)';

angles = (-180:1:180)';

%% Create mast/spec Excel
mastMedian = 10 + 1.5*sin(freqFull/2);
mastPeak   = 13 + 1.5*sin(freqFull/2);

specMedian = 6 + 0.5*cos(freqFull/3);
specPeak   = 8 + 0.5*cos(freqFull/3);

specTbl = table(freqFull, mastMedian, mastPeak, specMedian, specPeak, ...
    'VariableNames', {'FrequencyGHz','MastMedian','MastPeak','SpecMedian','SpecPeak'});

writetable(specTbl, fullfile(rootDir, "mast_and_spec.xlsx"));

%% Create weighting/reasoning Excel
weightTbl = table();
weightTbl.FrequencyGHz = freqFull;
weightTbl.Performance = nan(size(freqFull));

weightTbl.W_Pos_lt_1   = 1.0 * ones(size(freqFull));
weightTbl.W_Pos_1_to_3 = 0.7 * ones(size(freqFull));
weightTbl.W_Pos_gt_3   = 0.4 * ones(size(freqFull));

weightTbl.W_Neg_lt_1   = 2.0 * ones(size(freqFull));
weightTbl.W_Neg_1_to_3 = 4.0 * ones(size(freqFull));
weightTbl.W_Neg_gt_3   = 8.0 * ones(size(freqFull));

weightTbl.WeightedFOM = nan(size(freqFull));

weightTbl.Reason_Pos_lt_1   = repmat("Small positive margin; unit is slightly better than specification.", size(freqFull));
weightTbl.Reason_Pos_1_to_3 = repmat("Moderate positive margin; unit has comfortable margin.", size(freqFull));
weightTbl.Reason_Pos_gt_3   = repmat("Large positive margin; unit strongly exceeds requirement.", size(freqFull));

weightTbl.Reason_Neg_lt_1   = repmat("Small negative miss; unit is slightly below specification.", size(freqFull));
weightTbl.Reason_Neg_1_to_3 = repmat("Moderate negative miss; unit is meaningfully below specification.", size(freqFull));
weightTbl.Reason_Neg_gt_3   = repmat("Large negative miss; unit has severe performance shortfall.", size(freqFull));

writetable(weightTbl, fullfile(rootDir, "weighting_reasoning.xlsx"));

%% Create unit measurement files
for u = 1:numel(units)

    unitName = units(u);
    unitFolder = fullfile(rootDir, unitName);

    if ~exist(unitFolder, "dir")
        mkdir(unitFolder);
    end

    unitOffset = (u - 1) * 0.8;

    for p = 1:numel(pols)

        pol = pols(p);

        if pol == "Hpol"
            polOffset = 0;
        else
            polOffset = 0.5;
        end

        data_2_6  = makeMockPattern(angles, freq_2_6, unitOffset, polOffset);
        data_6_18 = makeMockPattern(angles, freq_6_18, unitOffset, polOffset);

        file_2_6  = fullfile(unitFolder, unitName + "_" + pol + "_2-6GHz.xlsx");
        file_6_18 = fullfile(unitFolder, unitName + "_" + pol + "_6-18GHz.xlsx");

        saveMeasurementExcel(file_2_6, angles, freq_2_6, data_2_6);
        saveMeasurementExcel(file_6_18, angles, freq_6_18, data_6_18);

    end
end

disp("Mock three-input dataset generated at:");
disp(rootDir);

%% ========================================================================
function data = makeMockPattern(angles, freqGHz, unitOffset, polOffset)

    nAngles = numel(angles);
    nFreq = numel(freqGHz);

    data = zeros(nAngles, nFreq);

    for k = 1:nFreq

        f = freqGHz(k);

        %% Angular pattern
        angleShape = 1.2*cosd(angles).^2;

        %% Baseline response
        baseline = 8.5 + unitOffset + polOffset;

        %% Slow frequency variation
        freqRipple = 0.8*sin(0.9*f) + 0.35*cos(1.8*f);

        %% Deep resonant nulls / depths
        dip1 = -12.0 * exp(-((f - 4.0).^2)  / 0.08);
        dip2 = -8.0  * exp(-((f - 5.6).^2)  / 0.12);
        dip3 = -24.0 * exp(-((f - 6.9).^2)  / 0.06);
        dip4 = -10.0 * exp(-((f - 8.8).^2)  / 0.05);
        dip5 = -14.0 * exp(-((f - 9.8).^2)  / 0.04);

        %% Extra clear dips near your desired examples
        dip6 = -9.0  * exp(-((f - 11.0).^2) / 0.18);
        dip7 = -7.5  * exp(-((f - 15.0).^2) / 0.16);

        noise = 0.18 * randn(nAngles, 1);

        data(:,k) = baseline + angleShape + freqRipple + ...
                    dip1 + dip2 + dip3 + dip4 + dip5 + dip6 + dip7 + noise;

    end
end
function saveMeasurementExcel(filename, angles, freqGHz, data)

    out = cell(length(angles)+1, length(freqGHz)+1);

    out{1,1} = "Angle/Freq";

    for k = 1:length(freqGHz)
        out{1,k+1} = freqGHz(k);
    end

    for k = 1:length(angles)
        out{k+1,1} = angles(k);
    end

    for r = 1:length(angles)
        for c = 1:length(freqGHz)
            out{r+1,c+1} = data(r,c);
        end
    end

    writecell(out, filename);

end