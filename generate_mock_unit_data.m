%% generate_mock_unit_data.m
clear; clc;

rootDir = fullfile(pwd, "MockUnitData");

if ~exist(rootDir, "dir")
    mkdir(rootDir);
end

rng(1);

units = ["Unit01", "Unit02", "Unit03","Unit04"];
pols = ["Hpol", "Vpol"];

freq_2_6  = 2:0.1:6;
freq_6_18 = 6:0.1:18;

angles = (-179:1:180)';

%% Mast/spec full frequency grid
freqFull = (2:0.1:18)';

mastMedian = 10 + 1.5*sin(freqFull/2);
mastPeak   = 13 + 1.5*sin(freqFull/2);

specMedian = 6 + 0.5*cos(freqFull/3);
specPeak   = 8 + 0.5*cos(freqFull/3);

specTbl = table(freqFull, mastMedian, mastPeak, specMedian, specPeak, ...
    'VariableNames', {'FrequencyGHz','MastMedian','MastPeak','SpecMedian','SpecPeak'});

writetable(specTbl, fullfile(rootDir, "mast_and_spec.xlsx"));

%% Generate unit measurement files
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

disp("Mock data generated at:");
disp(rootDir);

%% Helper: create mock measurement pattern
function data = makeMockPattern(angles, freqGHz, unitOffset, polOffset)

    nAngles = numel(angles);
    nFreq = numel(freqGHz);

    data = zeros(nAngles, nFreq);

    for k = 1:nFreq

        f = freqGHz(k);

        angleShape = 2.5*cosd(angles).^2;
        freqShape = 0.8*sin(f/2);
        noise = 0.4 * randn(nAngles, 1);

        data(:,k) = 5.5 + unitOffset + polOffset + freqShape + angleShape + noise;

    end
end

%% Helper: save with frequency row and angle column
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