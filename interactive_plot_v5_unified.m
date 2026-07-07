%% interactive_plot_v5_unified.m
% Same analysis/functionality as separate-window version, but all non-heatmap plots are in one tabbed GUI.
clear; clc;

delete(findall(groot,'Tag','UnitPerformanceGUI'));
delete(findall(groot,'Tag','PolarHeatmapViewer'));

rootDir = fullfile(pwd,"MockUnitData");
unitsToCompare = ["Unit01","Unit02","Unit03"];   % <-- edit this list for 20+ units
pols = ["Hpol","Vpol"];

data = UnitPerfLib.loadAndAnalyze(rootDir,unitsToCompare,pols);
disp(data.summaryRows);
launchUnifiedDashboard(data);

function launchUnifiedDashboard(data)
    allResults=data.allResults; summaryRows=data.summaryRows; patternDB=data.patternDB;
    specFreq=data.specFreq; specMedian=data.specMedian; specPeak=data.specPeak; bandSummary=data.bandSummary;

    uniqueUnits = unique(string(summaryRows.Unit),'stable');
    uniquePols = unique(string(summaryRows.Polarization),'stable');

    fig = uifigure('Name','Unit Performance Analysis Dashboard - Unified', ...
        'Position',[60 60 1600 880], 'Tag','UnitPerformanceGUI');

    mainGrid = uigridlayout(fig,[1 2]);
    mainGrid.ColumnWidth = {310,'1x'};
    mainGrid.RowHeight = {'1x'};
    mainGrid.Padding = [8 8 8 8];

    controlPanel = uipanel(mainGrid,'Title','Controls','Scrollable','on');
    nRows = numel(uniqueUnits)+numel(uniquePols)+23;
    controlGrid = uigridlayout(controlPanel,[nRows 1]);
    controlGrid.RowHeight = repmat({'fit'},1,nRows);
    controlGrid.Padding = [8 8 8 8];
    controlGrid.RowSpacing = 8;

    uilabel(controlGrid,'Text','Units','FontWeight','bold');
    unitCB = gobjects(numel(uniqueUnits),1);
    for i=1:numel(uniqueUnits)
        unitCB(i)=uicheckbox(controlGrid,'Text',uniqueUnits(i),'Value',true);
    end

    uilabel(controlGrid,'Text','Polarization','FontWeight','bold');
    polCB = gobjects(numel(uniquePols),1);
    for i=1:numel(uniquePols)
        polCB(i)=uicheckbox(controlGrid,'Text',uniquePols(i),'Value',true);
    end

    uilabel(controlGrid,'Text','Analysis Metric','FontWeight','bold');
    metricDrop = uidropdown(controlGrid,'Items',["Median","Peak"],'Value',"Peak");

    uilabel(controlGrid,'Text','Band of Interest GHz','FontWeight','bold');
    bandEdit = uieditfield(controlGrid,'text','Value','', ...
        'Placeholder','Example: 4.5-5.5, 10-12, 14-16');

    uilabel(controlGrid,'Text','BOI Mode','FontWeight','bold');
    boiModeDrop = uidropdown(controlGrid,'Items',["Use all frequencies","Only band(s) of interest"], ...
        'Value',"Use all frequencies");

    uilabel(controlGrid,'Text','Polar Cut Frequency GHz','FontWeight','bold');
    freqDrop = uidropdown(controlGrid,'Items',string(specFreq), ...
        'Value',string(specFreq(round(numel(specFreq)/2))));

    uilabel(controlGrid,'Text','Polar Cut Normalization','FontWeight','bold');
    normDrop = uidropdown(controlGrid,'Items',["Raw","Normalize to max"],'Value',"Raw");

    uilabel(controlGrid,'Text','Bandwidth Display','FontWeight','bold');
    showBandsCB = uicheckbox(controlGrid,'Text','Show bandwidth regions','Value',true);
    showCenterCB = uicheckbox(controlGrid,'Text','Show center markers','Value',true);
    show3dBCB = uicheckbox(controlGrid,'Text','Show 3 dB lines','Value',true);

    updateBtn = uibutton(controlGrid,'Text','Update Current Tab');
    heatmapBtn = uibutton(controlGrid,'Text','Open Polar Heatmap Viewer');
    closeBtn = uibutton(controlGrid,'Text','Close Dashboard');

    tabGroup = uitabgroup(mainGrid);
    tabOverview = uitab(tabGroup,'Title','Overview');
    tabFreq = uitab(tabGroup,'Title','Frequency');
    tabPolar = uitab(tabGroup,'Title','Polar Cut');
    tabBand = uitab(tabGroup,'Title','Bandwidth');
    tabRecommend = uitab(tabGroup,'Title','Recommendation');

    gridOverview = uigridlayout(tabOverview,[1 1]); gridOverview.Padding=[8 8 8 8]; axFOM = uiaxes(gridOverview);

    gridFreq = uigridlayout(tabFreq,[2 1]); gridFreq.RowHeight={'1x','1x'}; gridFreq.Padding=[8 8 8 8];
    axMedian = uiaxes(gridFreq); axPeak = uiaxes(gridFreq);

    gridPolar = uigridlayout(tabPolar,[1 1]); gridPolar.Padding=[8 8 8 8]; axPolar = polaraxes(gridPolar);

    gridBand = uigridlayout(tabBand,[2 2]); gridBand.RowHeight={'2x','1x'}; gridBand.ColumnWidth={'3x','1x'}; gridBand.Padding=[8 8 8 8];
    axBand = uiaxes(gridBand); axBand.Layout.Row=1; axBand.Layout.Column=[1 2];
    bandTableUI = uitable(gridBand); bandTableUI.Layout.Row=2; bandTableUI.Layout.Column=1;
    helpPanel = uipanel(gridBand,'Title','How to Read'); helpPanel.Layout.Row=2; helpPanel.Layout.Column=2;
    helpGrid = uigridlayout(helpPanel,[6 1]); helpGrid.RowHeight=repmat({'fit'},1,6); helpGrid.Padding=[8 8 8 8];
    uilabel(helpGrid,'Text','Bandwidth = Right 3 dB freq - Left 3 dB freq');
    uilabel(helpGrid,'Text','Center freq = minimum measured value inside band');
    uilabel(helpGrid,'Text','3 dB level = average of surrounding peaks - 3 dB');
    uilabel(helpGrid,'Text','Dashed lines = 3 dB crossing frequencies');
    uilabel(helpGrid,'Text','Black marker = center frequency');
    uilabel(helpGrid,'Text','Shaded region = detected bandwidth');

    gridRec = uigridlayout(tabRecommend,[2 2]); gridRec.RowHeight={'1x','1.25x'}; gridRec.ColumnWidth={'1x','1x'}; gridRec.Padding=[8 8 8 8];
    axRec = uiaxes(gridRec); axRec.Layout.Row=1; axRec.Layout.Column=1;
    axRecFail = uiaxes(gridRec); axRecFail.Layout.Row=1; axRecFail.Layout.Column=2;
    recText = uitextarea(gridRec,'Editable','off'); recText.Layout.Row=2; recText.Layout.Column=[1 2];

    isUpdating = false;
    updateBtn.ButtonPushedFcn = @(src,event) safeUpdate();
    closeBtn.ButtonPushedFcn = @(src,event) closeDashboard();
    heatmapBtn.ButtonPushedFcn = @(src,event) UnitPerfLib.openPolarHeatmapViewer(patternDB);
    tabGroup.SelectionChangedFcn = @(src,event) safeUpdate();

    % For 20+ units, controls do not auto-redraw. Click Update Current Tab.
    tabGroup.SelectedTab = tabOverview;
    safeUpdate();

    function safeUpdate()
        if isUpdating || ~isvalid(fig), return; end
        isUpdating = true;
        try
            fig.Pointer='watch'; drawnow limitrate;
            updateCurrentTab();
        catch ME
            warning(ME.message);
        end
        if isvalid(fig), fig.Pointer='arrow'; end
        isUpdating = false;
        drawnow limitrate;
    end

    function closeDashboard()
        isUpdating=false;
        delete(findall(groot,'Tag','UnitPerformanceGUI'));
        drawnow force;
    end

    function [selectedMask,selectedLabels,metric,boiRanges,useBOI] = getSelections()
        selectedUnits = strings(0);
        for k=1:numel(unitCB), if unitCB(k).Value, selectedUnits(end+1)=uniqueUnits(k); end, end
        selectedPols = strings(0);
        for k=1:numel(polCB), if polCB(k).Value, selectedPols(end+1)=uniquePols(k); end, end
        selectedMask = ismember(string(summaryRows.Unit),selectedUnits) & ismember(string(summaryRows.Polarization),selectedPols);
        selectedLabels = string(summaryRows.Label(selectedMask));
        metric = string(metricDrop.Value);
        boiRanges = UnitPerfLib.parseBandInterestString(bandEdit.Value);
        useBOI = boiModeDrop.Value == "Only band(s) of interest";
    end

    function updateCurrentTab()
        [selectedMask,selectedLabels,metric,boiRanges,useBOI] = getSelections();
        switch string(tabGroup.SelectedTab.Title)
            case "Overview"
                recTbl = UnitPerfLib.buildRecommendationTable(allResults,summaryRows,selectedMask,metric,boiRanges,useBOI);
                cla(axFOM); if ~isempty(recTbl), bar(axFOM,categorical(recTbl.Label),recTbl.TotalWeightedFOM); ylabel(axFOM,"Weighted FOM"); title(axFOM,"Weighted FOM Comparison"); grid(axFOM,"on"); end
            case "Frequency"
                cla(axMedian); hold(axMedian,"on");
                for k=1:numel(selectedLabels), idx=string(allResults.Label)==selectedLabels(k); plot(axMedian,allResults.FrequencyGHz(idx),allResults.MeasuredMedian(idx),'DisplayName',selectedLabels(k),'LineWidth',1.25); end
                plot(axMedian,specFreq,specMedian,'k--','LineWidth',2,'DisplayName','Spec Median'); UnitPerfLib.shadeBOI(axMedian,boiRanges,useBOI); title(axMedian,"Measured Median vs Specification"); xlabel(axMedian,"Frequency GHz"); ylabel(axMedian,"Measured Median"); legend(axMedian,'Location','best'); grid(axMedian,"on"); hold(axMedian,"off");
                cla(axPeak); hold(axPeak,"on");
                for k=1:numel(selectedLabels), idx=string(allResults.Label)==selectedLabels(k); plot(axPeak,allResults.FrequencyGHz(idx),allResults.MeasuredPeak(idx),'DisplayName',selectedLabels(k),'LineWidth',1.25); end
                plot(axPeak,specFreq,specPeak,'k--','LineWidth',2,'DisplayName','Spec Peak'); UnitPerfLib.shadeBOI(axPeak,boiRanges,useBOI); title(axPeak,"Measured Peak vs Specification"); xlabel(axPeak,"Frequency GHz"); ylabel(axPeak,"Measured Peak"); legend(axPeak,'Location','best'); grid(axPeak,"on"); hold(axPeak,"off");
            case "Polar Cut"
                cla(axPolar); hold(axPolar,"on"); selectedFreq=str2double(freqDrop.Value); actualFreqs=[];
                for k=1:numel(patternDB)
                    thisLabel=string(patternDB(k).Label); if ~ismember(thisLabel,selectedLabels), continue; end
                    [~,idxF]=min(abs(patternDB(k).FrequencyGHz-selectedFreq)); pattern=patternDB(k).Pattern(:,idxF);
                    if normDrop.Value=="Normalize to max", pattern=pattern-max(pattern); end
                    actualFreqs(end+1)=patternDB(k).FrequencyGHz(idxF);
                    polarplot(axPolar,deg2rad(patternDB(k).AnglesDeg),pattern,'DisplayName',thisLabel,'LineWidth',1.5);
                end
                if isempty(actualFreqs), title(axPolar,"Polar Cut"); else, title(axPolar,sprintf("Polar Cut @ %.2f GHz",mean(actualFreqs))); end
                if ~isempty(selectedLabels), lgd=legend(axPolar,'Location','southoutside','NumColumns',3,'FontSize',8); lgd.Box='off'; end
                hold(axPolar,"off");
            case "Bandwidth"
                UnitPerfLib.plotBandwidthAxis(axBand,allResults,bandSummary,selectedLabels,metric,boiRanges,useBOI,showBandsCB.Value,showCenterCB.Value,show3dBCB.Value,true);
                bandMask = ismember(string(bandSummary.Label),selectedLabels) & string(bandSummary.Metric)==metric;
                if useBOI && ~isempty(boiRanges), bandMask = bandMask & UnitPerfLib.isFrequencyInBands(bandSummary.CenterFrequencyGHz,boiRanges); end
                T = UnitPerfLib.reorderBandwidthTable(bandSummary(bandMask,:)); bandTableUI.Data=T; if ~isempty(T), bandTableUI.ColumnName=T.Properties.VariableNames; end
            case "Recommendation"
                recTbl = UnitPerfLib.buildRecommendationTable(allResults,summaryRows,selectedMask,metric,boiRanges,useBOI);
                cla(axRec); cla(axRecFail);
                if isempty(recTbl), recText.Value="No units selected."; return; end
                bar(axRec,categorical(recTbl.Label),recTbl.TotalWeightedFOM); ylabel(axRec,"Weighted FOM"); title(axRec,"Recommended Ranking - "+metric); grid(axRec,"on");
                bar(axRecFail,categorical(recTbl.Label),recTbl.NumFailFrequencies); ylabel(axRecFail,"Failing Frequencies"); title(axRecFail,"Fail Count in Analysis Band"); grid(axRecFail,"on");
                recText.Value = UnitPerfLib.buildRecommendationText(recTbl(1,:),recTbl,metric,boiRanges,useBOI);
        end
    end
end
