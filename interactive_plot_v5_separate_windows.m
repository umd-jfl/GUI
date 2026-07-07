%% interactive_plot_v5_separate_windows.m
% Same analysis/functionality as unified version, but every plot has an individual figure window.
clear; clc;

delete(findall(groot,'Tag','UnitPerformanceGUI'));
delete(findall(groot,'Tag','PolarHeatmapViewer'));

rootDir = fullfile(pwd,"MockUnitData");
unitsToCompare = ["Unit01","Unit02","Unit03"];   % <-- edit this list for 20+ units
pols = ["Hpol","Vpol"];

data = UnitPerfLib.loadAndAnalyze(rootDir,unitsToCompare,pols);
disp(data.summaryRows);
launchSeparateWindowDashboard(data);

function launchSeparateWindowDashboard(data)
    allResults=data.allResults; summaryRows=data.summaryRows; patternDB=data.patternDB;
    specFreq=data.specFreq; specMedian=data.specMedian; specPeak=data.specPeak; bandSummary=data.bandSummary;

    uniqueUnits = unique(string(summaryRows.Unit),'stable');
    uniquePols = unique(string(summaryRows.Polarization),'stable');

    figCtrl = uifigure('Name','Controls - Separate Windows','Position',[50 100 340 800],'Tag','UnitPerformanceGUI');
    ctrl = uigridlayout(figCtrl,[numel(uniqueUnits)+numel(uniquePols)+23 1]);
    ctrl.RowHeight = repmat({'fit'},1,numel(uniqueUnits)+numel(uniquePols)+23);
    ctrl.Padding = [8 8 8 8]; ctrl.RowSpacing = 8;
    figCtrl.Scrollable = 'on';

    uilabel(ctrl,'Text','Units','FontWeight','bold');
    unitCB = gobjects(numel(uniqueUnits),1);
    for i=1:numel(uniqueUnits), unitCB(i)=uicheckbox(ctrl,'Text',uniqueUnits(i),'Value',true); end

    uilabel(ctrl,'Text','Polarization','FontWeight','bold');
    polCB = gobjects(numel(uniquePols),1);
    for i=1:numel(uniquePols), polCB(i)=uicheckbox(ctrl,'Text',uniquePols(i),'Value',true); end

    uilabel(ctrl,'Text','Analysis Metric','FontWeight','bold');
    metricDrop = uidropdown(ctrl,'Items',["Median","Peak"],'Value',"Peak");

    uilabel(ctrl,'Text','Band of Interest GHz','FontWeight','bold');
    bandEdit = uieditfield(ctrl,'text','Placeholder','Example: 4.5-5.5, 10-12, 14-16');

    uilabel(ctrl,'Text','BOI Mode','FontWeight','bold');
    boiModeDrop = uidropdown(ctrl,'Items',["Use all frequencies","Only band(s) of interest"],'Value',"Use all frequencies");

    uilabel(ctrl,'Text','Polar Cut Frequency GHz','FontWeight','bold');
    freqDrop = uidropdown(ctrl,'Items',string(specFreq),'Value',string(specFreq(round(numel(specFreq)/2))));

    uilabel(ctrl,'Text','Polar Cut Normalization','FontWeight','bold');
    normDrop = uidropdown(ctrl,'Items',["Raw","Normalize to max"],'Value',"Raw");

    uilabel(ctrl,'Text','Bandwidth Display','FontWeight','bold');
    showBandsCB = uicheckbox(ctrl,'Text','Show bandwidth regions','Value',true);
    showCenterCB = uicheckbox(ctrl,'Text','Show center markers','Value',true);
    show3dBCB = uicheckbox(ctrl,'Text','Show 3 dB lines','Value',true);

    updateBtn = uibutton(ctrl,'Text','Update All Windows');
    heatmapBtn = uibutton(ctrl,'Text','Open Polar Heatmap Viewer');
    closeBtn = uibutton(ctrl,'Text','Close All Windows');

    figFOM = uifigure('Name','Overview - Weighted FOM','Position',[410 580 560 340],'Tag','UnitPerformanceGUI'); axFOM = uiaxes(figFOM);
    figFreq = uifigure('Name','Frequency','Position',[990 500 720 470],'Tag','UnitPerformanceGUI'); gFreq = uigridlayout(figFreq,[2 1]); axMedian = uiaxes(gFreq); axPeak = uiaxes(gFreq);
    figPolar = uifigure('Name','Polar Cut','Position',[410 60 620 500],'Tag','UnitPerformanceGUI'); axPolar = polaraxes(figPolar,'Position',[0.08 0.16 0.84 0.76]);
    figBand = uifigure('Name','Bandwidth','Position',[1050 60 850 500],'Tag','UnitPerformanceGUI'); gBand = uigridlayout(figBand,[2 1]); gBand.RowHeight={'2x','1x'}; axBand = uiaxes(gBand); bandTableUI = uitable(gBand);
    figRec = uifigure('Name','Recommendation','Position',[50 30 340 560],'Tag','UnitPerformanceGUI'); gRec = uigridlayout(figRec,[3 1]); gRec.RowHeight={'1x','1x','1.4x'}; axRec = uiaxes(gRec); axRecFail = uiaxes(gRec); recText = uitextarea(gRec,'Editable','off');

    isUpdating = false;
    updateBtn.ButtonPushedFcn = @(src,event) safeUpdate();
    heatmapBtn.ButtonPushedFcn = @(src,event) UnitPerfLib.openPolarHeatmapViewer(patternDB);
    closeBtn.ButtonPushedFcn = @(src,event) closeAll();
    safeUpdate();

    function safeUpdate()
        if isUpdating, return; end
        isUpdating = true;
        try
            figCtrl.Pointer='watch'; drawnow limitrate;
            updateAllWindows();
        catch ME
            warning(ME.message);
        end
        if isvalid(figCtrl), figCtrl.Pointer='arrow'; end
        isUpdating=false;
        drawnow limitrate;
    end

    function closeAll()
        isUpdating=false;
        delete(findall(groot,'Tag','UnitPerformanceGUI'));
        drawnow force;
    end

    function [selectedMask,selectedLabels,metric,boiRanges,useBOI] = getSelections()
        selectedUnits = strings(0); for k=1:numel(unitCB), if unitCB(k).Value, selectedUnits(end+1)=uniqueUnits(k); end, end
        selectedPols = strings(0); for k=1:numel(polCB), if polCB(k).Value, selectedPols(end+1)=uniquePols(k); end, end
        selectedMask = ismember(string(summaryRows.Unit),selectedUnits) & ismember(string(summaryRows.Polarization),selectedPols);
        selectedLabels = string(summaryRows.Label(selectedMask)); metric = string(metricDrop.Value);
        boiRanges = UnitPerfLib.parseBandInterestString(bandEdit.Value); useBOI = boiModeDrop.Value == "Only band(s) of interest";
    end

    function updateAllWindows()
        [selectedMask,selectedLabels,metric,boiRanges,useBOI] = getSelections();
        recTbl = UnitPerfLib.buildRecommendationTable(allResults,summaryRows,selectedMask,metric,boiRanges,useBOI);

        cla(axFOM); if ~isempty(recTbl), bar(axFOM,categorical(recTbl.Label),recTbl.TotalWeightedFOM); ylabel(axFOM,"Weighted FOM"); title(axFOM,"Weighted FOM Comparison"); grid(axFOM,"on"); end

        cla(axMedian); hold(axMedian,"on");
        for k=1:numel(selectedLabels), idx=string(allResults.Label)==selectedLabels(k); plot(axMedian,allResults.FrequencyGHz(idx),allResults.MeasuredMedian(idx),'DisplayName',selectedLabels(k),'LineWidth',1.25); end
        plot(axMedian,specFreq,specMedian,'k--','LineWidth',2,'DisplayName','Spec Median'); UnitPerfLib.shadeBOI(axMedian,boiRanges,useBOI); title(axMedian,"Measured Median vs Specification"); xlabel(axMedian,"Frequency GHz"); ylabel(axMedian,"Measured Median"); legend(axMedian,'Location','best'); grid(axMedian,"on"); hold(axMedian,"off");
        cla(axPeak); hold(axPeak,"on");
        for k=1:numel(selectedLabels), idx=string(allResults.Label)==selectedLabels(k); plot(axPeak,allResults.FrequencyGHz(idx),allResults.MeasuredPeak(idx),'DisplayName',selectedLabels(k),'LineWidth',1.25); end
        plot(axPeak,specFreq,specPeak,'k--','LineWidth',2,'DisplayName','Spec Peak'); UnitPerfLib.shadeBOI(axPeak,boiRanges,useBOI); title(axPeak,"Measured Peak vs Specification"); xlabel(axPeak,"Frequency GHz"); ylabel(axPeak,"Measured Peak"); legend(axPeak,'Location','best'); grid(axPeak,"on"); hold(axPeak,"off");

        cla(axPolar); hold(axPolar,"on"); selectedFreq=str2double(freqDrop.Value); actualFreqs=[];
        for k=1:numel(patternDB)
            thisLabel=string(patternDB(k).Label); if ~ismember(thisLabel,selectedLabels), continue; end
            [~,idxF]=min(abs(patternDB(k).FrequencyGHz-selectedFreq)); pattern=patternDB(k).Pattern(:,idxF); if normDrop.Value=="Normalize to max", pattern=pattern-max(pattern); end
            actualFreqs(end+1)=patternDB(k).FrequencyGHz(idxF); polarplot(axPolar,deg2rad(patternDB(k).AnglesDeg),pattern,'DisplayName',thisLabel,'LineWidth',1.5);
        end
        if isempty(actualFreqs), title(axPolar,"Polar Cut"); else, title(axPolar,sprintf("Polar Cut @ %.2f GHz",mean(actualFreqs))); end
        if ~isempty(selectedLabels), lgd=legend(axPolar,'Location','southoutside','NumColumns',3,'FontSize',8); lgd.Box='off'; end
        hold(axPolar,"off");

        UnitPerfLib.plotBandwidthAxis(axBand,allResults,bandSummary,selectedLabels,metric,boiRanges,useBOI,showBandsCB.Value,showCenterCB.Value,show3dBCB.Value,true);
        bandMask = ismember(string(bandSummary.Label),selectedLabels) & string(bandSummary.Metric)==metric;
        if useBOI && ~isempty(boiRanges), bandMask=bandMask & UnitPerfLib.isFrequencyInBands(bandSummary.CenterFrequencyGHz,boiRanges); end
        T = UnitPerfLib.reorderBandwidthTable(bandSummary(bandMask,:)); bandTableUI.Data=T; if ~isempty(T), bandTableUI.ColumnName=T.Properties.VariableNames; end

        cla(axRec); cla(axRecFail);
        if ~isempty(recTbl)
            bar(axRec,categorical(recTbl.Label),recTbl.TotalWeightedFOM); ylabel(axRec,"Weighted FOM"); title(axRec,"Recommended Ranking - "+metric); grid(axRec,"on");
            bar(axRecFail,categorical(recTbl.Label),recTbl.NumFailFrequencies); ylabel(axRecFail,"Failing Frequencies"); title(axRecFail,"Fail Count in Analysis Band"); grid(axRecFail,"on");
            recText.Value = UnitPerfLib.buildRecommendationText(recTbl(1,:),recTbl,metric,boiRanges,useBOI);
        else
            recText.Value = "No units selected.";
        end
    end
end
