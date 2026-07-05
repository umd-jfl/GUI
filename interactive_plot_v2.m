%% interactive_plot_v3.m
clear; clc;
delete(findall(groot,'Tag','UnitPerformanceGUI'));

rootDir = fullfile(pwd,"MockUnitData");

unitsToCompare = ["Unit01","Unit02","Unit03"];
pols = ["Hpol","Vpol"];

specFile = fullfile(rootDir,"mast_and_spec.xlsx");
weightFile = fullfile(rootDir,"weighting_reasoning.xlsx");

specTbl = readtable(specFile);
weightTbl = readtable(weightFile);

specFreq = specTbl.FrequencyGHz;
specMedian = specTbl.SpecMedian;
specPeak = specTbl.SpecPeak;

allResults = table();
summaryRows = table();
weightedDetailAll = table();
patternDB = struct();
patternCount = 0;

%% Process measurements
for u = 1:numel(unitsToCompare)

    unitName = unitsToCompare(u);
    unitFolder = fullfile(rootDir,unitName);

    for p = 1:numel(pols)

        pol = pols(p);

        file_2_6 = findFile(unitFolder,pol,"2-6");
        file_6_18 = findFile(unitFolder,pol,"6-18");

        [angles_2_6,freq_2_6,data_2_6] = readMeasurementExcel(file_2_6);
        [~,freq_6_18,data_6_18] = readMeasurementExcel(file_6_18);

        med_2_6 = median(data_2_6,1,"omitnan")';
        pk_2_6 = max(data_2_6,[],1,"omitnan")';

        med_6_18 = median(data_6_18,1,"omitnan")';
        pk_6_18 = max(data_6_18,[],1,"omitnan")';

        keep_6_18 = freq_6_18 > 6;

        combinedFreq = [freq_2_6(:); freq_6_18(keep_6_18)];
        combinedMedian = [med_2_6(:); med_6_18(keep_6_18)];
        combinedPeak = [pk_2_6(:); pk_6_18(keep_6_18)];
        combinedPattern = [data_2_6, data_6_18(:,keep_6_18)];

        [combinedFreq,idxSort] = sort(combinedFreq);
        combinedMedian = combinedMedian(idxSort);
        combinedPeak = combinedPeak(idxSort);
        combinedPattern = combinedPattern(:,idxSort);

        measuredMedian = interp1(combinedFreq,combinedMedian,specFreq,"linear",NaN);
        measuredPeak = interp1(combinedFreq,combinedPeak,specFreq,"linear",NaN);

        performanceMedian = specMedian - measuredMedian;
        performancePeak = specPeak - measuredPeak;

        [valueMedian,weightMedian,reasonMedian,binMedian] = ...
            computeWeightedFOM(specFreq,performanceMedian,weightTbl);

        [valuePeak,weightPeak,reasonPeak,binPeak] = ...
            computeWeightedFOM(specFreq,performancePeak,weightTbl);

        fomMedian = sum(valueMedian,"omitnan");
        fomPeak = sum(valuePeak,"omitnan");

        label = unitName + "_" + pol;

        T = table();
        T.Unit = repmat(unitName,numel(specFreq),1);
        T.Polarization = repmat(pol,numel(specFreq),1);
        T.Label = repmat(label,numel(specFreq),1);
        T.FrequencyGHz = specFreq;

        T.SpecMedian = specMedian;
        T.MeasuredMedian = measuredMedian;
        T.PerformanceMedian = performanceMedian;
        T.WeightMedian = weightMedian;
        T.ValueMedian = valueMedian;
        T.ReasonMedian = reasonMedian;
        T.BinMedian = binMedian;

        T.SpecPeak = specPeak;
        T.MeasuredPeak = measuredPeak;
        T.PerformancePeak = performancePeak;
        T.WeightPeak = weightPeak;
        T.ValuePeak = valuePeak;
        T.ReasonPeak = reasonPeak;
        T.BinPeak = binPeak;

        T.FOMMedian = repmat(fomMedian,numel(specFreq),1);
        T.FOMPeak = repmat(fomPeak,numel(specFreq),1);

        allResults = [allResults; T];

        S = table(unitName,pol,label,fomMedian,fomPeak, ...
            'VariableNames',{'Unit','Polarization','Label','FOMMedian','FOMPeak'});
        summaryRows = [summaryRows; S];

        weightedDetailAll = [weightedDetailAll; ...
            makeWeightedDetailRows(unitName,pol,label,"Median",specFreq,performanceMedian,weightMedian,valueMedian,reasonMedian,binMedian); ...
            makeWeightedDetailRows(unitName,pol,label,"Peak",specFreq,performancePeak,weightPeak,valuePeak,reasonPeak,binPeak)];

        patternCount = patternCount + 1;
        patternDB(patternCount).Unit = unitName;
        patternDB(patternCount).Polarization = pol;
        patternDB(patternCount).Label = label;
        patternDB(patternCount).AnglesDeg = angles_2_6(:);
        patternDB(patternCount).FrequencyGHz = combinedFreq(:);
        patternDB(patternCount).Pattern = combinedPattern;

    end
end

bandSummary = detectAllBandwidths(allResults);

writetable(allResults,fullfile(rootDir,"PerFrequency_WeightedFOM_Results.xlsx"));
writetable(summaryRows,fullfile(rootDir,"Summary_WeightedFOM_Results.xlsx"));
writetable(weightedDetailAll,fullfile(rootDir,"WeightedFOM_Detail_Output.xlsx"));
writetable(bandSummary,fullfile(rootDir,"Detected_Bandwidths.xlsx"));

disp(summaryRows);

launchDashboard(allResults,summaryRows,patternDB,specFreq,specMedian,specPeak,bandSummary);

%% ========================================================================
function launchDashboard(allResults,summaryRows,patternDB,specFreq,specMedian,specPeak,bandSummary)

    uniqueUnits = unique(string(summaryRows.Unit),'stable');
    uniquePols = unique(string(summaryRows.Polarization),'stable');
    labels = string(summaryRows.Label);

    fig = uifigure('Name','Unit Performance Analysis Dashboard', ...
        'Position',[60 60 1600 880], ...
        'Tag','UnitPerformanceGUI');

    mainGrid = uigridlayout(fig,[1 2]);
    mainGrid.ColumnWidth = {310,'1x'};
    mainGrid.RowHeight = {'1x'};
    mainGrid.Padding = [8 8 8 8];
    mainGrid.ColumnSpacing = 8;

    %% Controls
    controlPanel = uipanel(mainGrid, ...
        'Title','Controls', ...
        'Scrollable','on');

    nRows = numel(uniqueUnits) + numel(uniquePols) + 24;

    controlGrid = uigridlayout(controlPanel,[nRows 1]);
    controlGrid.RowHeight = repmat({'fit'},1,nRows);
    controlGrid.Padding = [8 8 8 8];
    controlGrid.RowSpacing = 8;

    uilabel(controlGrid,'Text','Units','FontWeight','bold');

    unitCB = gobjects(numel(uniqueUnits),1);
    for i = 1:numel(uniqueUnits)
        unitCB(i) = uicheckbox(controlGrid,'Text',uniqueUnits(i),'Value',true);
    end

    uilabel(controlGrid,'Text','Polarization','FontWeight','bold');

    polCB = gobjects(numel(uniquePols),1);
    for i = 1:numel(uniquePols)
        polCB(i) = uicheckbox(controlGrid,'Text',uniquePols(i),'Value',true);
    end

    uilabel(controlGrid,'Text','Analysis Metric','FontWeight','bold');
    measuredMetricDrop = uidropdown(controlGrid,'Items',["Median","Peak"],'Value',"Peak");

    uilabel(controlGrid,'Text','Band of Interest GHz','FontWeight','bold');
    bandEdit = uieditfield(controlGrid,'text', ...
        'Value','', ...
        'Placeholder','Example: 4.5-5.5, 10-12, 14-16');

    uilabel(controlGrid,'Text','BOI Mode','FontWeight','bold');
    boiModeDrop = uidropdown(controlGrid, ...
        'Items',["Use all frequencies","Only band(s) of interest"], ...
        'Value',"Use all frequencies");

    uilabel(controlGrid,'Text','Polar Cut Frequency GHz','FontWeight','bold');
    freqDrop = uidropdown(controlGrid,'Items',string(specFreq), ...
        'Value',string(specFreq(round(numel(specFreq)/2))));

    uilabel(controlGrid,'Text','Polar Cut Normalization','FontWeight','bold');
    normDrop = uidropdown(controlGrid,'Items',["Raw","Normalize to max"],'Value',"Raw");

    uilabel(controlGrid,'Text','Heatmap Unit/Pol','FontWeight','bold');
    heatmapDrop = uidropdown(controlGrid,'Items',labels,'Value',labels(1));

    uilabel(controlGrid,'Text','Heatmap Normalization','FontWeight','bold');
    heatmapNormDrop = uidropdown(controlGrid, ...
        'Items',["Raw","Normalize each frequency","Normalize global max"], ...
        'Value',"Raw");

    uilabel(controlGrid,'Text','Bandwidth Display','FontWeight','bold');

    showBandsCB = uicheckbox(controlGrid,'Text','Show bandwidth regions','Value',true);
    showCenterCB = uicheckbox(controlGrid,'Text','Show center markers','Value',true);
    show3dBCB = uicheckbox(controlGrid,'Text','Show 3 dB lines','Value',true);

    updateBtn = uibutton(controlGrid,'Text','Update Plots');
    closeBtn = uibutton(controlGrid,'Text','Close Dashboard');

    %% Tabs
    tabGroup = uitabgroup(mainGrid);

    tabOverview = uitab(tabGroup,'Title','Overview');
    tabFreq = uitab(tabGroup,'Title','Frequency');
    tabPolar = uitab(tabGroup,'Title','Polar');
    tabBand = uitab(tabGroup,'Title','Bandwidth');
    tabRecommend = uitab(tabGroup,'Title','Recommendation');

    %% Overview tab
    gridOverview = uigridlayout(tabOverview,[1 1]);
    gridOverview.Padding = [8 8 8 8];
    axFOM = uiaxes(gridOverview);

    %% Frequency tab
    gridFreq = uigridlayout(tabFreq,[2 1]);
    gridFreq.RowHeight = {'1x','1x'};
    gridFreq.Padding = [8 8 8 8];

    axMedian = uiaxes(gridFreq);
    axPeak = uiaxes(gridFreq);

    %% Polar tab
    gridPolar = uigridlayout(tabPolar,[1 2]);
    gridPolar.ColumnWidth = {'1x','1x'};
    gridPolar.Padding = [8 8 8 8];

    polarPanel = uipanel(gridPolar,'Title','Polar Cut');
    polarGrid = uigridlayout(polarPanel,[1 1]);
    polarGrid.Padding = [8 8 8 8];
    axPolar = polaraxes(polarGrid);

    heatPanel = uipanel(gridPolar,'Title','Polar Frequency-Angle Heatmap');
    heatGrid = uigridlayout(heatPanel,[1 1]);
    heatGrid.Padding = [8 8 8 8];
    axHeat = uiaxes(heatGrid);

    %% Bandwidth tab
    gridBand = uigridlayout(tabBand,[2 2]);
    gridBand.RowHeight = {'2x','1x'};
    gridBand.ColumnWidth = {'3x','1x'};
    gridBand.Padding = [8 8 8 8];

    axBand = uiaxes(gridBand);
    axBand.Layout.Row = 1;
    axBand.Layout.Column = [1 2];

    bandTableUI = uitable(gridBand);
    bandTableUI.Layout.Row = 2;
    bandTableUI.Layout.Column = 1;

    helpPanel = uipanel(gridBand,'Title','How to Read');
    helpPanel.Layout.Row = 2;
    helpPanel.Layout.Column = 2;

    helpGrid = uigridlayout(helpPanel,[6 1]);
    helpGrid.RowHeight = repmat({'fit'},1,6);
    helpGrid.Padding = [8 8 8 8];

    uilabel(helpGrid,'Text','Bandwidth = Right 3 dB freq - Left 3 dB freq');
    uilabel(helpGrid,'Text','Center freq = minimum measured value inside band');
    uilabel(helpGrid,'Text','3 dB level = average of surrounding peaks - 3 dB');
    uilabel(helpGrid,'Text','Dashed lines = 3 dB crossing frequencies');
    uilabel(helpGrid,'Text','Black marker = center frequency');
    uilabel(helpGrid,'Text','Shaded region = detected bandwidth');

    %% Recommendation tab
    gridRec = uigridlayout(tabRecommend,[2 2]);
    gridRec.RowHeight = {'1x','1.25x'};
    gridRec.ColumnWidth = {'1x','1x'};
    gridRec.Padding = [8 8 8 8];

    axRec = uiaxes(gridRec);
    axRec.Layout.Row = 1;
    axRec.Layout.Column = 1;

    axRecFail = uiaxes(gridRec);
    axRecFail.Layout.Row = 1;
    axRecFail.Layout.Column = 2;

    recText = uitextarea(gridRec,'Editable','off');
    recText.Layout.Row = 2;
    recText.Layout.Column = [1 2];

    %% Callbacks
    updateBtn.ButtonPushedFcn = @(src,event) safeUpdate();
    closeBtn.ButtonPushedFcn = @(src,event) closeDashboard();
    tabGroup.SelectionChangedFcn = @(src,event) safeUpdate();

    allControls = [unitCB; polCB; showBandsCB; showCenterCB; show3dBCB];

    for i = 1:numel(allControls)
        allControls(i).ValueChangedFcn = @(src,event) safeUpdate();
    end

    measuredMetricDrop.ValueChangedFcn = @(src,event) safeUpdate();
    freqDrop.ValueChangedFcn = @(src,event) safeUpdate();
    normDrop.ValueChangedFcn = @(src,event) safeUpdate();
    heatmapDrop.ValueChangedFcn = @(src,event) safeUpdate();
    heatmapNormDrop.ValueChangedFcn = @(src,event) safeUpdate();
    boiModeDrop.ValueChangedFcn = @(src,event) safeUpdate();
    bandEdit.ValueChangedFcn = @(src,event) safeUpdate();

    safeUpdate();

    %% Safe update wrapper
    function safeUpdate()
        try
            updatePlots();
            drawnow limitrate;
        catch ME
            warning(ME.message);
        end
    end

    %% Close helper
    function closeDashboard()
        delete(findall(groot,'Tag','UnitPerformanceGUI'));
        drawnow;
    end

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

        selectedMask = ismember(string(summaryRows.Unit),selectedUnits) & ...
                       ismember(string(summaryRows.Polarization),selectedPols);

        selectedLabels = string(summaryRows.Label(selectedMask));
        selectedMetric = string(measuredMetricDrop.Value);

        boiRanges = parseBandInterestString(bandEdit.Value);
        useBOI = boiModeDrop.Value == "Only band(s) of interest";

        activeTab = string(tabGroup.SelectedTab.Title);

        switch activeTab
            case "Overview"
                updateOverview();

            case "Frequency"
                updateFrequency();

            case "Polar"
                updatePolar();

            case "Bandwidth"
                updateBandwidth();

            case "Recommendation"
                updateRecommendation();
        end

        %% Overview update
        function updateOverview()

            cla(axFOM);

            recTblAll = buildRecommendationTable( ...
                allResults,summaryRows,selectedMask,selectedMetric,boiRanges,useBOI);

            if ~isempty(recTblAll)
                bar(axFOM,categorical(recTblAll.Label),recTblAll.TotalWeightedFOM);
                ylabel(axFOM,"Weighted FOM");
                title(axFOM,"Weighted FOM Comparison");
                grid(axFOM,"on");
            end
        end

        %% Frequency update
        function updateFrequency()

            cla(axMedian);
            hold(axMedian,"on");

            for kk = 1:numel(selectedLabels)
                idx = string(allResults.Label) == selectedLabels(kk);
                plot(axMedian,allResults.FrequencyGHz(idx),allResults.MeasuredMedian(idx), ...
                    'DisplayName',selectedLabels(kk),'LineWidth',1.25);
            end

            plot(axMedian,specFreq,specMedian,'k--','LineWidth',2,'DisplayName','Spec Median');
            shadeBOI(axMedian,boiRanges,useBOI);
            title(axMedian,"Measured Median vs Specification");
            xlabel(axMedian,"Frequency GHz");
            ylabel(axMedian,"Measured Median");
            legend(axMedian,'Location','best');
            grid(axMedian,"on");
            hold(axMedian,"off");

            cla(axPeak);
            hold(axPeak,"on");

            for kk = 1:numel(selectedLabels)
                idx = string(allResults.Label) == selectedLabels(kk);
                plot(axPeak,allResults.FrequencyGHz(idx),allResults.MeasuredPeak(idx), ...
                    'DisplayName',selectedLabels(kk),'LineWidth',1.25);
            end

            plot(axPeak,specFreq,specPeak,'k--','LineWidth',2,'DisplayName','Spec Peak');
            shadeBOI(axPeak,boiRanges,useBOI);
            title(axPeak,"Measured Peak vs Specification");
            xlabel(axPeak,"Frequency GHz");
            ylabel(axPeak,"Measured Peak");
            legend(axPeak,'Location','best');
            grid(axPeak,"on");
            hold(axPeak,"off");
        end

        %% Bandwidth update
        function updateBandwidth()

            plotBandwidthAxis(axBand,selectedLabels,selectedMetric,true,boiRanges,useBOI);

            bandMask = ismember(string(bandSummary.Label),selectedLabels) & ...
                       string(bandSummary.Metric) == selectedMetric;

            if useBOI && ~isempty(boiRanges)
                bandMask = bandMask & isFrequencyInBands(bandSummary.CenterFrequencyGHz,boiRanges);
            end

            thisBandTable = bandSummary(bandMask,:);
            thisBandTable = reorderBandwidthTable(thisBandTable);

            bandTableUI.Data = thisBandTable;

            if ~isempty(thisBandTable)
                bandTableUI.ColumnName = thisBandTable.Properties.VariableNames;
            end
        end

        %% Polar update
        function updatePolar()

            cla(axPolar);
            hold(axPolar,"on");

            selectedFreq = str2double(freqDrop.Value);
            actualFreqs = [];

            for kk = 1:numel(patternDB)

                thisLabel = string(patternDB(kk).Label);

                if ~ismember(thisLabel,selectedLabels)
                    continue;
                end

                freqs = patternDB(kk).FrequencyGHz;
                [~,idxFreq] = min(abs(freqs-selectedFreq));

                anglesDeg = patternDB(kk).AnglesDeg;
                pattern = patternDB(kk).Pattern(:,idxFreq);

                if normDrop.Value == "Normalize to max"
                    pattern = pattern - max(pattern);
                end

                actualFreqs(end+1) = freqs(idxFreq);

                polarplot(axPolar,deg2rad(anglesDeg),pattern, ...
                    'DisplayName',thisLabel,'LineWidth',1.5);
            end

            if isempty(actualFreqs)
                title(axPolar,"Polar Cut");
            else
                title(axPolar,sprintf("Polar Cut @ %.2f GHz",mean(actualFreqs)));
            end

            if ~isempty(selectedLabels)
                lgd = legend(axPolar,'Location','southoutside','NumColumns',3,'FontSize',8);
                lgd.Box = 'off';
            end

            hold(axPolar,"off");

            plotPolarHeatmap();
        end

        %% Recommendation update
        function updateRecommendation()

            cla(axRec);
            cla(axRecFail);

            recTblAll = buildRecommendationTable( ...
                allResults,summaryRows,selectedMask,selectedMetric,boiRanges,useBOI);

            if isempty(recTblAll)
                recText.Value = "No units selected.";
                return;
            end

            bar(axRec,categorical(recTblAll.Label),recTblAll.TotalWeightedFOM);
            ylabel(axRec,"Weighted FOM");
            title(axRec,"Recommended Ranking - " + selectedMetric);
            grid(axRec,"on");

            bar(axRecFail,categorical(recTblAll.Label),recTblAll.NumFailFrequencies);
            ylabel(axRecFail,"Failing Frequencies");
            title(axRecFail,"Fail Count in Analysis Band");
            grid(axRecFail,"on");

            bestRow = recTblAll(1,:);
            recText.Value = buildRecommendationText(bestRow,recTblAll,selectedMetric,boiRanges,useBOI);
        end
    end

    %% Bandwidth helper
    function plotBandwidthAxis(ax,selectedLabels,selectedMetric,annotateText,boiRanges,useBOI)

        cla(ax);
        hold(ax,"on");

        for kk = 1:numel(selectedLabels)

            idx = string(allResults.Label) == selectedLabels(kk);
            f = allResults.FrequencyGHz(idx);

            if selectedMetric == "Median"
                y = allResults.MeasuredMedian(idx);
            else
                y = allResults.MeasuredPeak(idx);
            end

            plot(ax,f,y,'DisplayName',selectedLabels(kk)+" "+selectedMetric,'LineWidth',1.25);

            thisBand = bandSummary(string(bandSummary.Label)==selectedLabels(kk) & ...
                string(bandSummary.Metric)==selectedMetric,:);

            if useBOI && ~isempty(boiRanges)
                thisBand = thisBand(isFrequencyInBands(thisBand.CenterFrequencyGHz,boiRanges),:);
            end

            for b = 1:height(thisBand)

                xL = thisBand.Left3dBFrequencyGHz(b);
                xR = thisBand.Right3dBFrequencyGHz(b);
                xC = thisBand.CenterFrequencyGHz(b);
                yC = thisBand.CenterMeasuredValue(b);
                bw = thisBand.BandwidthGHz(b);

                if showBandsCB.Value
                    xregion(ax,xL,xR,'FaceAlpha',0.08,'HandleVisibility','off');
                end

                if show3dBCB.Value
                    xline(ax,xL,'k:','HandleVisibility','off');
                    xline(ax,xR,'k:','HandleVisibility','off');
                end

                if showCenterCB.Value
                    plot(ax,xC,yC,'ko','MarkerFaceColor','k','HandleVisibility','off');

                    if annotateText
                        text(ax,xC,yC,sprintf("CF %.2f GHz\nBW %.2f GHz",xC,bw), ...
                            'FontSize',9,'VerticalAlignment','bottom','HorizontalAlignment','center');
                    end
                end
            end
        end

        shadeBOI(ax,boiRanges,useBOI);
        xlabel(ax,"Frequency GHz");
        ylabel(ax,"Measured "+selectedMetric);
        title(ax,"Measured "+selectedMetric+" vs Frequency with Bandwidths");
        legend(ax,'Location','best');
        grid(ax,"on");
        hold(ax,"off");
    end

    %% Heatmap helper
    function plotPolarHeatmap()

        cla(axHeat);

        selectedHeatLabel = string(heatmapDrop.Value);
        idxDB = find(string({patternDB.Label}) == selectedHeatLabel,1);

        if isempty(idxDB)
            return;
        end

        freqs = patternDB(idxDB).FrequencyGHz(:);
        anglesDeg = patternDB(idxDB).AnglesDeg(:);
        pattern = patternDB(idxDB).Pattern;

        switch heatmapNormDrop.Value
            case "Raw"
                plotPattern = pattern;
            case "Normalize each frequency"
                plotPattern = pattern - max(pattern,[],1);
            case "Normalize global max"
                plotPattern = pattern - max(pattern(:));
        end

        hold(axHeat,"on");

        for fIdx = 1:numel(freqs)

            r = freqs(fIdx)*ones(size(anglesDeg));
            theta = deg2rad(anglesDeg);
            x = r.*cos(theta);
            y = r.*sin(theta);
            c = plotPattern(:,fIdx);

            h = scatter(axHeat,x,y,18,c,'filled','HandleVisibility','off');
            h.DataTipTemplate.DataTipRows(1) = dataTipTextRow("Frequency GHz",repmat(freqs(fIdx),size(anglesDeg)));
            h.DataTipTemplate.DataTipRows(2) = dataTipTextRow("Angle deg",anglesDeg);
            h.DataTipTemplate.DataTipRows(3) = dataTipTextRow("Measured",c);
        end

        colormap(axHeat,turbo);
        cbHeat = colorbar(axHeat);
        cbHeat.Label.String = "Measured Value";

        ringFreqs = linspace(min(freqs),max(freqs),5);
        thetaFine = linspace(deg2rad(min(anglesDeg)),deg2rad(max(anglesDeg)),720);

        for rr = ringFreqs
            plot(axHeat,rr*cos(thetaFine),rr*sin(thetaFine),'k:','LineWidth',0.75,'HandleVisibility','off');
            text(axHeat,rr*cos(deg2rad(max(anglesDeg))),rr*sin(deg2rad(max(anglesDeg))), ...
                sprintf("%.1f GHz",rr),'FontSize',9,'HorizontalAlignment','left');
        end

        angleMin = min(anglesDeg);
        angleMax = max(anglesDeg);
        angleSpan = angleMax - angleMin;

        if angleSpan >= 300
            angleTicks = -180:45:180;
        elseif angleSpan >= 180
            angleTicks = angleMin:30:angleMax;
        else
            angleTicks = angleMin:15:angleMax;
        end

        angleTicks = angleTicks(angleTicks >= angleMin & angleTicks <= angleMax);

        for aa = angleTicks
            theta = deg2rad(aa);
            plot(axHeat,[min(freqs) max(freqs)]*cos(theta), ...
                [min(freqs) max(freqs)]*sin(theta),'k:','LineWidth',0.75,'HandleVisibility','off');

            text(axHeat,1.06*max(freqs)*cos(theta),1.06*max(freqs)*sin(theta), ...
                sprintf("%.0f°",aa),'FontSize',9,'HorizontalAlignment','center');
        end

        axis(axHeat,'equal');
        margin = 1.15*max(freqs);
        xlim(axHeat,[-margin margin]);
        ylim(axHeat,[-margin margin]);

        axHeat.XTick = [];
        axHeat.YTick = [];
        axHeat.Box = 'off';

        title(axHeat,"Polar Frequency-Angle Heatmap: "+selectedHeatLabel);

        hold(axHeat,"off");
    end
end
%% ========================================================================
function [value,weight,reason,binName] = computeWeightedFOM(freqGHz,performance,weightTbl)

    n = numel(freqGHz);
    value = nan(n,1);
    weight = nan(n,1);
    reason = strings(n,1);
    binName = strings(n,1);

    for i = 1:n
        [~,idxWeight] = min(abs(weightTbl.FrequencyGHz - freqGHz(i)));
        weightRow = weightTbl(idxWeight,:);
        [w,r,b] = selectWeightAndReason(performance(i),weightRow);
        weight(i) = w;
        reason(i) = r;
        binName(i) = b;
        value(i) = performance(i)*w;
    end
end

function [weight,reason,binName] = selectWeightAndReason(performance,weightRow)

    if isnan(performance)
        weight = NaN;
        reason = "";
        binName = "";
        return;
    end

    if performance >= 0
        if performance < 1
            weight = weightRow.W_Pos_lt_1;
            reason = string(weightRow.Reason_Pos_lt_1);
            binName = "Positive <1 dB";
        elseif performance <= 3
            weight = weightRow.W_Pos_1_to_3;
            reason = string(weightRow.Reason_Pos_1_to_3);
            binName = "Positive 1-3 dB";
        else
            weight = weightRow.W_Pos_gt_3;
            reason = string(weightRow.Reason_Pos_gt_3);
            binName = "Positive >3 dB";
        end
    else
        absPerf = abs(performance);

        if absPerf < 1
            weight = weightRow.W_Neg_lt_1;
            reason = string(weightRow.Reason_Neg_lt_1);
            binName = "Negative <1 dB";
        elseif absPerf <= 3
            weight = weightRow.W_Neg_1_to_3;
            reason = string(weightRow.Reason_Neg_1_to_3);
            binName = "Negative 1-3 dB";
        else
            weight = weightRow.W_Neg_gt_3;
            reason = string(weightRow.Reason_Neg_gt_3);
            binName = "Negative >3 dB";
        end
    end
end

function T = makeWeightedDetailRows(unitName,pol,label,metric,freq,perf,weight,value,reason,binName)

    T = table();
    T.Unit = repmat(unitName,numel(freq),1);
    T.Polarization = repmat(pol,numel(freq),1);
    T.Label = repmat(label,numel(freq),1);
    T.Metric = repmat(metric,numel(freq),1);
    T.FrequencyGHz = freq;
    T.Performance = perf;
    T.SelectedWeight = weight;
    T.WeightedFOM = value;
    T.PerformanceBin = binName;
    T.Reason = reason;
end

function bandSummary = detectAllBandwidths(allResults)

    labels = unique(string(allResults.Label),'stable');
    bandSummary = table();

    for i = 1:numel(labels)
        label = labels(i);
        idx = string(allResults.Label) == label;
        T = allResults(idx,:);

        Bmed = detectBandwidthsFromMeasuredCurve(T.FrequencyGHz,T.MeasuredMedian,label,"Median");
        Bpeak = detectBandwidthsFromMeasuredCurve(T.FrequencyGHz,T.MeasuredPeak,label,"Peak");

        bandSummary = [bandSummary; Bmed; Bpeak];
    end
end

function bandTbl = detectBandwidthsFromMeasuredCurve(freqGHz,measured,label,metricName)

    freqGHz = freqGHz(:);
    measured = measured(:);

    valid = ~isnan(freqGHz) & ~isnan(measured);
    freqGHz = freqGHz(valid);
    measured = measured(valid);

    bandTbl = table();

    if numel(freqGHz) < 5
        return;
    end

    y = smoothdata(measured,"movmean",2);

    minIdx = find(islocalmin(y));
    maxIdx = find(islocalmax(y));

    bandCount = 0;

    for m = 1:numel(minIdx)

        idxMin = minIdx(m);

        leftPeaks = maxIdx(maxIdx < idxMin);
        rightPeaks = maxIdx(maxIdx > idxMin);

        if isempty(leftPeaks) || isempty(rightPeaks)
            continue;
        end

        idxLeftPeak = leftPeaks(end);
        idxRightPeak = rightPeaks(1);

        avgPeak = mean([y(idxLeftPeak),y(idxRightPeak)]);
        threshold3dB = avgPeak - 3;

        leftCross = findCrossing(freqGHz(idxLeftPeak:idxMin),y(idxLeftPeak:idxMin),threshold3dB,"left");
        rightCross = findCrossing(freqGHz(idxMin:idxRightPeak),y(idxMin:idxRightPeak),threshold3dB,"right");

        if isnan(leftCross) || isnan(rightCross)
            continue;
        end

        bandMask = freqGHz >= leftCross & freqGHz <= rightCross;

        if ~any(bandMask)
            continue;
        end

        [centerMeasured,localIdx] = min(measured(bandMask));
        bandFreqs = freqGHz(bandMask);
        centerFreq = bandFreqs(localIdx);

        bandCount = bandCount + 1;

        newRow = table();
        newRow.Label = label;
        newRow.Metric = metricName;
        newRow.BandNumber = bandCount;
        newRow.CenterFrequencyGHz = centerFreq;
        newRow.BandwidthGHz = rightCross - leftCross;
        newRow.CenterMeasuredValue = centerMeasured;
        newRow.Left3dBFrequencyGHz = leftCross;
        newRow.Right3dBFrequencyGHz = rightCross;
        newRow.Threshold3dB = threshold3dB;
        newRow.AveragePeakMeasured = avgPeak;
        newRow.LeftPeakFrequencyGHz = freqGHz(idxLeftPeak);
        newRow.RightPeakFrequencyGHz = freqGHz(idxRightPeak);
        newRow.LeftPeakMeasured = measured(idxLeftPeak);
        newRow.RightPeakMeasured = measured(idxRightPeak);

        bandTbl = [bandTbl; newRow];
    end
end

function crossingFreq = findCrossing(freqGHz,y,threshold,side)

    crossingFreq = NaN;

    if side == "left"
        for k = numel(y):-1:2
            if (y(k-1)-threshold)*(y(k)-threshold) <= 0
                crossingFreq = interp1([y(k-1) y(k)],[freqGHz(k-1) freqGHz(k)],threshold);
                return;
            end
        end
    else
        for k = 1:numel(y)-1
            if (y(k)-threshold)*(y(k+1)-threshold) <= 0
                crossingFreq = interp1([y(k) y(k+1)],[freqGHz(k) freqGHz(k+1)],threshold);
                return;
            end
        end
    end
end

function recTbl = buildRecommendationTable(allResults,summaryRows,selectedMask,selectedMetric,boiRanges,useBOI)

    selectedLabels = string(summaryRows.Label(selectedMask));
    recTbl = table();

    for i = 1:numel(selectedLabels)

        label = selectedLabels(i);
        idx = string(allResults.Label) == label;
        T = allResults(idx,:);

        if useBOI && ~isempty(boiRanges)
            fMask = isFrequencyInBands(T.FrequencyGHz,boiRanges);
            T = T(fMask,:);
        end

        if isempty(T)
            continue;
        end

        if selectedMetric == "Median"
            values = T.ValueMedian;
            performance = T.PerformanceMedian;
            reasons = T.ReasonMedian;
            bins = T.BinMedian;
        else
            values = T.ValuePeak;
            performance = T.PerformancePeak;
            reasons = T.ReasonPeak;
            bins = T.BinPeak;
        end

        totalFOM = sum(values,"omitnan");
        avgPerformance = mean(performance,"omitnan");
        minPerformance = min(performance,[],"omitnan");
        nFail = sum(performance < 0,"omitnan");
        nPass = sum(performance >= 0,"omitnan");

        [worstContribution,worstIdx] = min(values,[],"omitnan");

        newRow = table();
        newRow.Label = label;
        newRow.TotalWeightedFOM = totalFOM;
        newRow.AveragePerformance = avgPerformance;
        newRow.MinimumPerformance = minPerformance;
        newRow.NumPassFrequencies = nPass;
        newRow.NumFailFrequencies = nFail;
        newRow.WorstWeightedContribution = worstContribution;
        newRow.WorstBin = bins(worstIdx);
        newRow.WorstReason = reasons(worstIdx);

        recTbl = [recTbl; newRow];
    end

    if ~isempty(recTbl)
        recTbl = sortrows(recTbl,"TotalWeightedFOM","descend");
    end
end

function txt = buildRecommendationText(bestRow,recTbl,selectedMetric,boiRanges,useBOI)

    txt = strings(0);

    if useBOI && ~isempty(boiRanges)
        bandText = bandRangesToText(boiRanges);
    else
        bandText = "all available frequencies";
    end

    txt(end+1) = "Recommended unit for " + selectedMetric + ": " + string(bestRow.Label);
    txt(end+1) = "Analysis band: " + bandText;
    txt(end+1) = "";
    txt(end+1) = "Why this unit is recommended:";
    txt(end+1) = "- It has the highest total weighted FOM among the selected units within the analysis band.";
    txt(end+1) = "- Total weighted FOM: " + sprintf("%.3f",bestRow.TotalWeightedFOM);
    txt(end+1) = "- Average performance margin: " + sprintf("%.3f dB",bestRow.AveragePerformance);
    txt(end+1) = "- Worst performance margin: " + sprintf("%.3f dB",bestRow.MinimumPerformance);
    txt(end+1) = "- Passing frequency points: " + string(bestRow.NumPassFrequencies);
    txt(end+1) = "- Failing frequency points: " + string(bestRow.NumFailFrequencies);
    txt(end+1) = "";
    txt(end+1) = "Most important concern for the selected unit:";
    txt(end+1) = "- Bin: " + string(bestRow.WorstBin);
    txt(end+1) = "- Reason: " + string(bestRow.WorstReason);

    if height(recTbl) > 1
        secondRow = recTbl(2,:);
        delta = bestRow.TotalWeightedFOM - secondRow.TotalWeightedFOM;

        txt(end+1) = "";
        txt(end+1) = "Comparison with next best:";
        txt(end+1) = "- Next best unit: " + string(secondRow.Label);
        txt(end+1) = "- Weighted FOM advantage: " + sprintf("%.3f",delta);
        txt(end+1) = "- Failing point difference: " + string(secondRow.NumFailFrequencies - bestRow.NumFailFrequencies);
    end
end

function ranges = parseBandInterestString(str)

    str = strtrim(string(str));
    ranges = zeros(0,2);

    if str == ""
        return;
    end

    parts = split(str,",");

    for i = 1:numel(parts)
        token = strtrim(parts(i));

        if contains(token,"-")
            nums = split(token,"-");
            if numel(nums) == 2
                a = str2double(strtrim(nums(1)));
                b = str2double(strtrim(nums(2)));

                if ~isnan(a) && ~isnan(b)
                    ranges(end+1,:) = sort([a b]);
                end
            end
        else
            c = str2double(token);
            if ~isnan(c)
                ranges(end+1,:) = [c c];
            end
        end
    end
end

function mask = isFrequencyInBands(freq,ranges)

    freq = freq(:);
    mask = false(size(freq));

    if isempty(ranges)
        mask(:) = true;
        return;
    end

    for i = 1:size(ranges,1)
        mask = mask | (freq >= ranges(i,1) & freq <= ranges(i,2));
    end
end

function txt = bandRangesToText(ranges)

    if isempty(ranges)
        txt = "all available frequencies";
        return;
    end

    parts = strings(size(ranges,1),1);
    for i = 1:size(ranges,1)
        parts(i) = sprintf("%.2f-%.2f GHz",ranges(i,1),ranges(i,2));
    end

    txt = strjoin(parts,", ");
end

function shadeBOI(ax,boiRanges,useBOI)

    if ~useBOI || isempty(boiRanges)
        return;
    end

    yl = ylim(ax);

    for i = 1:size(boiRanges,1)
        xregion(ax,boiRanges(i,1),boiRanges(i,2), ...
            'FaceAlpha',0.05, ...
            'HandleVisibility','off');
    end

    ylim(ax,yl);
end

function T = reorderBandwidthTable(T)

    if isempty(T)
        return;
    end

    preferredOrder = ["Label","Metric","BandNumber", ...
        "CenterFrequencyGHz","BandwidthGHz","CenterMeasuredValue", ...
        "Left3dBFrequencyGHz","Right3dBFrequencyGHz", ...
        "Threshold3dB","AveragePeakMeasured", ...
        "LeftPeakFrequencyGHz","RightPeakFrequencyGHz", ...
        "LeftPeakMeasured","RightPeakMeasured"];

    varNames = string(T.Properties.VariableNames);
    existingOrder = preferredOrder(ismember(preferredOrder,varNames));
    remainingOrder = varNames(~ismember(varNames,existingOrder));
    finalOrder = [existingOrder(:)' remainingOrder(:)'];

    T = T(:,finalOrder);
end

function filePath = findFile(folderPath,pol,bandText)

    files = dir(fullfile(folderPath,"*.xlsx"));
    names = string({files.name});

    match = contains(names,pol,"IgnoreCase",true) & ...
            contains(names,bandText,"IgnoreCase",true);

    matchedFiles = names(match);

    if isempty(matchedFiles)
        error("No file found for %s, %s in %s",pol,bandText,folderPath);
    elseif numel(matchedFiles) > 1
        error("Multiple files found for %s, %s in %s",pol,bandText,folderPath);
    end

    filePath = fullfile(folderPath,matchedFiles(1));
end

function [angles,freqGHz,data] = readMeasurementExcel(filename)

    raw = readcell(filename);

    freqGHz = cell2mat(raw(1,2:end));
    angles = cell2mat(raw(2:end,1));
    data = cell2mat(raw(2:end,2:end));

    freqGHz = freqGHz(:);
    angles = angles(:);
end