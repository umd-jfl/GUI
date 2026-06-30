%% compare_units_fom_interactive.m
clear; clc;

%% Close previous GUI windows from earlier runs
delete(findall(groot, 'Tag', 'UnitPerformanceGUI'));

rootDir = fullfile(pwd, "MockUnitData");

unitsToCompare = ["Unit01", "Unit02", "Unit03"];
pols = ["Hpol", "Vpol"];

specFile = fullfile(rootDir, "mast_and_spec.xlsx");

%% Read mast/spec
specTbl = readtable(specFile);

specFreq = specTbl.FrequencyGHz;

mastMedian = specTbl.MastMedian;
mastPeak   = specTbl.MastPeak;

specMedian = specTbl.SpecMedian;
specPeak   = specTbl.SpecPeak;

%% Output containers
allResults = table();
summaryRows = table();

patternDB = struct();
patternCount = 0;

%% Main processing
for u = 1:numel(unitsToCompare)

    unitName = unitsToCompare(u);
    unitFolder = fullfile(rootDir, unitName);

    for p = 1:numel(pols)

        pol = pols(p);

        file_2_6  = findFile(unitFolder, pol, "2-6");
        file_6_18 = findFile(unitFolder, pol, "6-18");

        [angles_2_6, freq_2_6, data_2_6] = readMeasurementExcel(file_2_6);
        [~, freq_6_18, data_6_18] = readMeasurementExcel(file_6_18);

        measuredMedian_2_6  = median(data_2_6, 1, "omitnan")';
        measuredPeak_2_6    = max(data_2_6, [], 1, "omitnan")';

        measuredMedian_6_18 = median(data_6_18, 1, "omitnan")';
        measuredPeak_6_18   = max(data_6_18, [], 1, "omitnan")';

        %% Use 6 GHz from 2-6 GHz only
        keep_6_18 = freq_6_18 > 6;

        combinedFreq = [freq_2_6(:); freq_6_18(keep_6_18)];
        combinedMedian = [measuredMedian_2_6(:); measuredMedian_6_18(keep_6_18)];
        combinedPeak   = [measuredPeak_2_6(:); measuredPeak_6_18(keep_6_18)];

        combinedPattern = [data_2_6, data_6_18(:, keep_6_18)];

        [combinedFreq, idxSort] = sort(combinedFreq);
        combinedMedian = combinedMedian(idxSort);
        combinedPeak   = combinedPeak(idxSort);
        combinedPattern = combinedPattern(:, idxSort);

        measuredMedian = interp1(combinedFreq, combinedMedian, specFreq, "linear", NaN);
        measuredPeak   = interp1(combinedFreq, combinedPeak, specFreq, "linear", NaN);

        %% FOM equations
        importanceMedian  = mastMedian - specMedian;
        performanceMedian = specMedian - measuredMedian;
        valueMedian       = performanceMedian .* importanceMedian;
        fomMedian         = sum(valueMedian, "omitnan");

        importancePeak  = mastPeak - specPeak;
        performancePeak = specPeak - measuredPeak;
        valuePeak       = performancePeak .* importancePeak;
        fomPeak         = sum(valuePeak, "omitnan");

        %% Store results
        label = unitName + "_" + pol;

        T = table();
        T.Unit = repmat(unitName, numel(specFreq), 1);
        T.Polarization = repmat(pol, numel(specFreq), 1);
        T.Label = repmat(label, numel(specFreq), 1);
        T.FrequencyGHz = specFreq;

        T.MastMedian = mastMedian;
        T.SpecMedian = specMedian;
        T.MeasuredMedian = measuredMedian;
        T.ImportanceMedian = importanceMedian;
        T.PerformanceMedian = performanceMedian;
        T.ValueMedian = valueMedian;

        T.MastPeak = mastPeak;
        T.SpecPeak = specPeak;
        T.MeasuredPeak = measuredPeak;
        T.ImportancePeak = importancePeak;
        T.PerformancePeak = performancePeak;
        T.ValuePeak = valuePeak;

        T.FOMMedian = repmat(fomMedian, numel(specFreq), 1);
        T.FOMPeak = repmat(fomPeak, numel(specFreq), 1);

        allResults = [allResults; T];

        S = table(unitName, pol, label, fomMedian, fomPeak, ...
            'VariableNames', {'Unit','Polarization','Label','FOMMedian','FOMPeak'});

        summaryRows = [summaryRows; S];

        patternCount = patternCount + 1;
        patternDB(patternCount).Unit = unitName;
        patternDB(patternCount).Polarization = pol;
        patternDB(patternCount).Label = label;
        patternDB(patternCount).AnglesDeg = angles_2_6(:);
        patternDB(patternCount).FrequencyGHz = combinedFreq(:);
        patternDB(patternCount).Pattern = combinedPattern;

    end
end

%% Save results
writetable(allResults, fullfile(rootDir, "PerFrequency_FOM_Results.xlsx"));
writetable(summaryRows, fullfile(rootDir, "Summary_FOM_Results.xlsx"));

disp(summaryRows);

%% Launch GUI
launchDashboard(allResults, summaryRows, patternDB, specFreq, specMedian, specPeak);

%% ========================================================================
function launchDashboard(allResults, summaryRows, patternDB, specFreq, specMedian, specPeak)

    uniqueUnits = unique(string(summaryRows.Unit), 'stable');
    uniquePols  = unique(string(summaryRows.Polarization), 'stable');
    labels = string(summaryRows.Label);

    posControl = [50 120 330 760];
    posFOM     = [400 560 540 360];
    posMedian  = [960 560 580 360];
    posPeak    = [1560 560 580 360];
    posPolar   = [400 80 700 520];
    posHeat    = [1120 60 820 620];

    %% Control panel
    figControl = uifigure('Name', 'Control Panel', ...
        'Position', posControl, ...
        'Tag', 'UnitPerformanceGUI');

    nRows = numel(uniqueUnits) + numel(uniquePols) + 14;
    controlGrid = uigridlayout(figControl, [nRows 1]);
    controlGrid.RowHeight = repmat({30}, 1, nRows);

    uilabel(controlGrid, 'Text', 'Units', 'FontWeight', 'bold');

    unitCB = gobjects(numel(uniqueUnits),1);
    for i = 1:numel(uniqueUnits)
        unitCB(i) = uicheckbox(controlGrid, ...
            'Text', uniqueUnits(i), ...
            'Value', true);
    end

    uilabel(controlGrid, 'Text', 'Polarization', 'FontWeight', 'bold');

    polCB = gobjects(numel(uniquePols),1);
    for i = 1:numel(uniquePols)
        polCB(i) = uicheckbox(controlGrid, ...
            'Text', uniquePols(i), ...
            'Value', true);
    end

    uilabel(controlGrid, 'Text', 'Polar Cut Frequency GHz', 'FontWeight', 'bold');

    freqDrop = uidropdown(controlGrid, ...
        'Items', string(specFreq), ...
        'Value', string(specFreq(round(numel(specFreq)/2))));

    uilabel(controlGrid, 'Text', 'Polar Cut Normalization', 'FontWeight', 'bold');

    normDrop = uidropdown(controlGrid, ...
        'Items', ["Raw", "Normalize to max"], ...
        'Value', "Raw");

    uilabel(controlGrid, 'Text', 'Polar Heatmap Unit/Pol', 'FontWeight', 'bold');

    heatmapDrop = uidropdown(controlGrid, ...
        'Items', labels, ...
        'Value', labels(1));

    uilabel(controlGrid, 'Text', 'Polar Heatmap Normalization', 'FontWeight', 'bold');

    heatmapNormDrop = uidropdown(controlGrid, ...
        'Items', ["Raw", "Normalize each frequency", "Normalize global max"], ...
        'Value', "Raw");

    updateBtn = uibutton(controlGrid, ...
        'Text', 'Update All Plots');

    closeBtn = uibutton(controlGrid, ...
        'Text', 'Close All GUI Windows');

    %% Plot windows
    figFOM = uifigure('Name', 'FOM Comparison', ...
        'Position', posFOM, ...
        'Tag', 'UnitPerformanceGUI');
    axFOM = uiaxes(figFOM, 'Position', [60 60 450 260]);

    figMedian = uifigure('Name', 'Measured Median vs Specification', ...
        'Position', posMedian, ...
        'Tag', 'UnitPerformanceGUI');
    axMedian = uiaxes(figMedian, 'Position', [65 60 480 260]);

    figPeak = uifigure('Name', 'Measured Peak vs Specification', ...
        'Position', posPeak, ...
        'Tag', 'UnitPerformanceGUI');
    axPeak = uiaxes(figPeak, 'Position', [65 60 480 260]);

    figPolar = uifigure('Name', 'Polar Cut', ...
        'Position', posPolar, ...
        'Tag', 'UnitPerformanceGUI');
    axPolar = polaraxes(figPolar, 'Position', [0.08 0.18 0.84 0.74]);

    figHeat = uifigure('Name', 'Polar Frequency-Angle Heatmap', ...
        'Position', posHeat, ...
        'Tag', 'UnitPerformanceGUI');
    axHeat = uiaxes(figHeat, 'Position', [70 55 640 500]);

    %% Callbacks
    updateBtn.ButtonPushedFcn = @(src,event) updatePlots();
    closeBtn.ButtonPushedFcn = @(src,event) delete(findall(groot, 'Tag', 'UnitPerformanceGUI'));

    for i = 1:numel(unitCB)
        unitCB(i).ValueChangedFcn = @(src,event) updatePlots();
    end

    for i = 1:numel(polCB)
        polCB(i).ValueChangedFcn = @(src,event) updatePlots();
    end

    freqDrop.ValueChangedFcn = @(src,event) updatePlots();
    normDrop.ValueChangedFcn = @(src,event) updatePlots();
    heatmapDrop.ValueChangedFcn = @(src,event) updatePlots();
    heatmapNormDrop.ValueChangedFcn = @(src,event) updatePlots();

    updatePlots();

    %% Main update function
    function updatePlots()

        selectedUnits = strings(0);
        for k = 1:numel(unitCB)
            if unitCB(k).Value
                selectedUnits(end+1) = uniqueUnits(k);
            end
        end

        selectedPols = strings(0);
        for k = 1:numel(polCB)
            if polCB(k).Value
                selectedPols(end+1) = uniquePols(k);
            end
        end

        selectedMask = ismember(string(summaryRows.Unit), selectedUnits) & ...
                       ismember(string(summaryRows.Polarization), selectedPols);

        selectedLabels = string(summaryRows.Label(selectedMask));

        %% FOM
        cla(axFOM);

        plotSummary = summaryRows(selectedMask,:);

        if ~isempty(plotSummary)
            bar(axFOM, categorical(plotSummary.Label), ...
                [plotSummary.FOMMedian plotSummary.FOMPeak]);

            ylabel(axFOM, "FOM");
            title(axFOM, "FOM Comparison");
            legend(axFOM, ["Median FOM", "Peak FOM"], 'Location', 'best');
            grid(axFOM, "on");
        end

        %% Median
        cla(axMedian);
        hold(axMedian, "on");

        for k = 1:numel(selectedLabels)
            idx = string(allResults.Label) == selectedLabels(k);

            plot(axMedian, ...
                allResults.FrequencyGHz(idx), ...
                allResults.MeasuredMedian(idx), ...
                'DisplayName', selectedLabels(k), ...
                'LineWidth', 1.25);
        end

        plot(axMedian, specFreq, specMedian, 'k--', ...
            'LineWidth', 2, ...
            'DisplayName', 'Spec Median');

        xlabel(axMedian, "Frequency GHz");
        ylabel(axMedian, "Measured Median");
        title(axMedian, "Measured Median vs Specification");
        legend(axMedian, 'Location', 'best');
        grid(axMedian, "on");
        hold(axMedian, "off");

        %% Peak
        cla(axPeak);
        hold(axPeak, "on");

        for k = 1:numel(selectedLabels)
            idx = string(allResults.Label) == selectedLabels(k);

            plot(axPeak, ...
                allResults.FrequencyGHz(idx), ...
                allResults.MeasuredPeak(idx), ...
                'DisplayName', selectedLabels(k), ...
                'LineWidth', 1.25);
        end

        plot(axPeak, specFreq, specPeak, 'k--', ...
            'LineWidth', 2, ...
            'DisplayName', 'Spec Peak');

        xlabel(axPeak, "Frequency GHz");
        ylabel(axPeak, "Measured Peak");
        title(axPeak, "Measured Peak vs Specification");
        legend(axPeak, 'Location', 'best');
        grid(axPeak, "on");
        hold(axPeak, "off");

        %% Polar cut
        cla(axPolar);
        hold(axPolar, "on");

        selectedFreq = str2double(freqDrop.Value);
        actualFreqs = [];

        for k = 1:numel(patternDB)

            thisLabel = string(patternDB(k).Label);

            if ~ismember(thisLabel, selectedLabels)
                continue;
            end

            freqs = patternDB(k).FrequencyGHz;
            [~, idxFreq] = min(abs(freqs - selectedFreq));

            anglesDeg = patternDB(k).AnglesDeg;
            pattern = patternDB(k).Pattern(:, idxFreq);

            if normDrop.Value == "Normalize to max"
                pattern = pattern - max(pattern);
            end

            actualFreqs(end+1) = freqs(idxFreq);

            theta = deg2rad(anglesDeg);

            polarplot(axPolar, theta, pattern, ...
                'DisplayName', thisLabel, ...
                'LineWidth', 1.5);

        end

        if isempty(actualFreqs)
            title(axPolar, "Polar Cut");
        else
            title(axPolar, sprintf("Polar Cut @ %.2f GHz", mean(actualFreqs)));
        end

        if ~isempty(selectedLabels)
            lgd = legend(axPolar, ...
                'Location', 'southoutside', ...
                'NumColumns', 3, ...
                'FontSize', 8);
            lgd.Box = 'off';
        end

        hold(axPolar, "off");

        %% Polar frequency-angle heatmap
        cla(axHeat);

        selectedHeatLabel = string(heatmapDrop.Value);
        idxDB = find(string({patternDB.Label}) == selectedHeatLabel, 1);

        if ~isempty(idxDB)

            freqs = patternDB(idxDB).FrequencyGHz(:);
            anglesDeg = patternDB(idxDB).AnglesDeg(:);
            pattern = patternDB(idxDB).Pattern;

            switch heatmapNormDrop.Value
                case "Raw"
                    plotPattern = pattern;
                case "Normalize each frequency"
                    plotPattern = pattern - max(pattern, [], 1);
                case "Normalize global max"
                    plotPattern = pattern - max(pattern(:));
            end

            cla(axHeat);
            hold(axHeat, "on");

            hList = gobjects(numel(freqs), 1);

            for fIdx = 1:numel(freqs)

                r = freqs(fIdx) * ones(size(anglesDeg));
                theta = deg2rad(anglesDeg);

                x = r .* cos(theta);
                y = r .* sin(theta);
                c = plotPattern(:, fIdx);

                hList(fIdx) = scatter(axHeat, x, y, 18, c, ...
                    'filled', ...
                    'DisplayName', sprintf("%.2f GHz", freqs(fIdx)));

                hList(fIdx).UserData.FrequencyGHz = freqs(fIdx);
                hList(fIdx).UserData.AnglesDeg = anglesDeg;
                hList(fIdx).UserData.Values = c;

                hList(fIdx).DataTipTemplate.DataTipRows(1) = dataTipTextRow("Frequency GHz", ...
                    repmat(freqs(fIdx), size(anglesDeg)));

                hList(fIdx).DataTipTemplate.DataTipRows(2) = dataTipTextRow("Angle deg", ...
                    anglesDeg);

                hList(fIdx).DataTipTemplate.DataTipRows(3) = dataTipTextRow("Measured", ...
                    c);

            end

            colormap(axHeat, turbo);
            cbHeat = colorbar(axHeat);
            cbHeat.Label.String = "Measured Value";

            %% Draw frequency rings
            ringFreqs = linspace(min(freqs), max(freqs), 5);
            thetaFine = linspace(deg2rad(min(anglesDeg)), deg2rad(max(anglesDeg)), 720);

            for rr = ringFreqs

                plot(axHeat, rr*cos(thetaFine), rr*sin(thetaFine), ...
                    'k:', 'LineWidth', 0.75, ...
                    'HandleVisibility', 'off');

                text(axHeat, rr*cos(deg2rad(max(anglesDeg))), ...
                    rr*sin(deg2rad(max(anglesDeg))), ...
                    sprintf("%.1f GHz", rr), ...
                    'FontSize', 9, ...
                    'HorizontalAlignment', 'left');

            end

            %% Draw adaptive angle spokes
            angleMin = min(anglesDeg);
            angleMax = max(anglesDeg);

            if angleMax - angleMin >= 300
                angleTicks = -180:45:180;
            elseif angleMax - angleMin >= 180
                angleTicks = angleMin:30:angleMax;
            else
                angleTicks = angleMin:15:angleMax;
            end

            angleTicks = angleTicks(angleTicks >= angleMin & angleTicks <= angleMax);

            for aa = angleTicks

                theta = deg2rad(aa);

                plot(axHeat, ...
                    [min(freqs) max(freqs)] * cos(theta), ...
                    [min(freqs) max(freqs)] * sin(theta), ...
                    'k:', ...
                    'LineWidth', 0.75, ...
                    'HandleVisibility', 'off');

                text(axHeat, ...
                    1.06*max(freqs)*cos(theta), ...
                    1.06*max(freqs)*sin(theta), ...
                    sprintf("%.0f°", aa), ...
                    'FontSize', 9, ...
                    'HorizontalAlignment', 'center');

            end

            axis(axHeat, 'equal');

            margin = 1.15 * max(freqs);
            xlim(axHeat, [-margin margin]);
            ylim(axHeat, [-margin margin]);

            axHeat.XTick = [];
            axHeat.YTick = [];
            axHeat.Box = 'off';

            title(axHeat, "Polar Frequency-Angle Heatmap: " + selectedHeatLabel);

            hold(axHeat, "off");

        end
    end
end

%% ========================================================================
function filePath = findFile(folderPath, pol, bandText)

    files = dir(fullfile(folderPath, "*.xlsx"));
    names = string({files.name});

    match = contains(names, pol, "IgnoreCase", true) & ...
            contains(names, bandText, "IgnoreCase", true);

    matchedFiles = names(match);

    if isempty(matchedFiles)
        error("No file found for %s, %s in %s", pol, bandText, folderPath);
    elseif numel(matchedFiles) > 1
        error("Multiple files found for %s, %s in %s", pol, bandText, folderPath);
    end

    filePath = fullfile(folderPath, matchedFiles(1));

end

function [angles, freqGHz, data] = readMeasurementExcel(filename)

    raw = readcell(filename);

    freqGHz = cell2mat(raw(1,2:end));
    angles  = cell2mat(raw(2:end,1));
    data    = cell2mat(raw(2:end,2:end));

    freqGHz = freqGHz(:);
    angles  = angles(:);

end

function edges = freqCentersToEdges(freqs)

    freqs = freqs(:);

    if numel(freqs) < 2
        edges = [freqs(1)-0.5; freqs(1)+0.5];
        return;
    end

    midpoints = (freqs(1:end-1) + freqs(2:end)) / 2;

    firstEdge = freqs(1) - (midpoints(1) - freqs(1));
    lastEdge  = freqs(end) + (freqs(end) - midpoints(end));

    edges = [firstEdge; midpoints; lastEdge];

end

function edges = angleCentersToEdges(theta)

    theta = theta(:);

    if numel(theta) < 2
        edges = [theta(1)-deg2rad(0.5); theta(1)+deg2rad(0.5)];
        return;
    end

    midpoints = (theta(1:end-1) + theta(2:end)) / 2;

    firstEdge = theta(1) - (midpoints(1) - theta(1));
    lastEdge  = theta(end) + (theta(end) - midpoints(end));

    edges = [firstEdge; midpoints; lastEdge];

end