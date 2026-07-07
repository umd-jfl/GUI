classdef UnitPerfLib
methods(Static)
function data = loadAndAnalyze(rootDir, unitsToCompare, pols)
    specFile = fullfile(rootDir,"mast_and_spec.xlsx");
    weightFile = fullfile(rootDir,"weighting_reasoning.xlsx");
    specTbl = readtable(specFile);
    weightTbl = readtable(weightFile);
    specFreq = specTbl.FrequencyGHz;
    specMedian = specTbl.SpecMedian;
    specPeak = specTbl.SpecPeak;
    allResults = table(); summaryRows = table(); weightedDetailAll = table();
    patternDB = struct(); patternCount = 0;
    for u = 1:numel(unitsToCompare)
        unitName = unitsToCompare(u); unitFolder = fullfile(rootDir,unitName);
        for p = 1:numel(pols)
            pol = pols(p);
            file_2_6 = UnitPerfLib.findFile(unitFolder,pol,"2-6");
            file_6_18 = UnitPerfLib.findFile(unitFolder,pol,"6-18");
            [angles_2_6,freq_2_6,data_2_6] = UnitPerfLib.readMeasurementExcel(file_2_6);
            [~,freq_6_18,data_6_18] = UnitPerfLib.readMeasurementExcel(file_6_18);
            med_2_6 = median(data_2_6,1,"omitnan")'; pk_2_6 = max(data_2_6,[],1,"omitnan")';
            med_6_18 = median(data_6_18,1,"omitnan")'; pk_6_18 = max(data_6_18,[],1,"omitnan")';
            keep_6_18 = freq_6_18 > 6;
            combinedFreq = [freq_2_6(:); freq_6_18(keep_6_18)];
            combinedMedian = [med_2_6(:); med_6_18(keep_6_18)];
            combinedPeak = [pk_2_6(:); pk_6_18(keep_6_18)];
            combinedPattern = [data_2_6, data_6_18(:,keep_6_18)];
            [combinedFreq,idxSort] = sort(combinedFreq);
            combinedMedian = combinedMedian(idxSort); combinedPeak = combinedPeak(idxSort);
            combinedPattern = combinedPattern(:,idxSort);
            measuredMedian = interp1(combinedFreq,combinedMedian,specFreq,"linear",NaN);
            measuredPeak = interp1(combinedFreq,combinedPeak,specFreq,"linear",NaN);
            performanceMedian = specMedian - measuredMedian; performancePeak = specPeak - measuredPeak;
            [valueMedian,weightMedian,reasonMedian,binMedian] = UnitPerfLib.computeWeightedFOM(specFreq,performanceMedian,weightTbl);
            [valuePeak,weightPeak,reasonPeak,binPeak] = UnitPerfLib.computeWeightedFOM(specFreq,performancePeak,weightTbl);
            fomMedian = sum(valueMedian,"omitnan"); fomPeak = sum(valuePeak,"omitnan");
            label = unitName + "_" + pol;
            T = table();
            T.Unit = repmat(unitName,numel(specFreq),1); T.Polarization = repmat(pol,numel(specFreq),1);
            T.Label = repmat(label,numel(specFreq),1); T.FrequencyGHz = specFreq;
            T.SpecMedian = specMedian; T.MeasuredMedian = measuredMedian; T.PerformanceMedian = performanceMedian;
            T.WeightMedian = weightMedian; T.ValueMedian = valueMedian; T.ReasonMedian = reasonMedian; T.BinMedian = binMedian;
            T.SpecPeak = specPeak; T.MeasuredPeak = measuredPeak; T.PerformancePeak = performancePeak;
            T.WeightPeak = weightPeak; T.ValuePeak = valuePeak; T.ReasonPeak = reasonPeak; T.BinPeak = binPeak;
            T.FOMMedian = repmat(fomMedian,numel(specFreq),1); T.FOMPeak = repmat(fomPeak,numel(specFreq),1);
            allResults = [allResults; T];
            S = table(unitName,pol,label,fomMedian,fomPeak,'VariableNames',{'Unit','Polarization','Label','FOMMedian','FOMPeak'});
            summaryRows = [summaryRows; S];
            weightedDetailAll = [weightedDetailAll; UnitPerfLib.makeWeightedDetailRows(unitName,pol,label,"Median",specFreq,performanceMedian,weightMedian,valueMedian,reasonMedian,binMedian); UnitPerfLib.makeWeightedDetailRows(unitName,pol,label,"Peak",specFreq,performancePeak,weightPeak,valuePeak,reasonPeak,binPeak)];
            patternCount = patternCount + 1;
            patternDB(patternCount).Unit = unitName; patternDB(patternCount).Polarization = pol; patternDB(patternCount).Label = label;
            patternDB(patternCount).AnglesDeg = angles_2_6(:); patternDB(patternCount).FrequencyGHz = combinedFreq(:); patternDB(patternCount).Pattern = combinedPattern;
        end
    end
    bandSummary = UnitPerfLib.detectAllBandwidths(allResults);
    writetable(allResults,fullfile(rootDir,"PerFrequency_WeightedFOM_Results.xlsx"));
    writetable(summaryRows,fullfile(rootDir,"Summary_WeightedFOM_Results.xlsx"));
    writetable(weightedDetailAll,fullfile(rootDir,"WeightedFOM_Detail_Output.xlsx"));
    writetable(bandSummary,fullfile(rootDir,"Detected_Bandwidths.xlsx"));
    data = struct('rootDir',rootDir,'allResults',allResults,'summaryRows',summaryRows,'patternDB',patternDB,'specFreq',specFreq,'specMedian',specMedian,'specPeak',specPeak,'bandSummary',bandSummary);
end

function filePath = findFile(folderPath,pol,bandText)
    files = dir(fullfile(folderPath,"*.xlsx")); names = string({files.name});
    match = contains(names,pol,"IgnoreCase",true) & contains(names,bandText,"IgnoreCase",true);
    matchedFiles = names(match);
    if isempty(matchedFiles), error("No file found for %s, %s in %s",pol,bandText,folderPath);
    elseif numel(matchedFiles)>1, error("Multiple files found for %s, %s in %s",pol,bandText,folderPath); end
    filePath = fullfile(folderPath,matchedFiles(1));
end

function [angles,freqGHz,data] = readMeasurementExcel(filename)
    raw = readcell(filename);
    freqGHz = cell2mat(raw(1,2:end)); angles = cell2mat(raw(2:end,1)); data = cell2mat(raw(2:end,2:end));
    freqGHz = freqGHz(:); angles = angles(:);
end

function [value,weight,reason,binName] = computeWeightedFOM(freqGHz,performance,weightTbl)
    n = numel(freqGHz); value = nan(n,1); weight = nan(n,1); reason = strings(n,1); binName = strings(n,1);
    for i = 1:n
        [~,idxWeight] = min(abs(weightTbl.FrequencyGHz - freqGHz(i)));
        [w,r,b] = UnitPerfLib.selectWeightAndReason(performance(i),weightTbl(idxWeight,:));
        weight(i)=w; reason(i)=r; binName(i)=b; value(i)=performance(i)*w;
    end
end

function [weight,reason,binName] = selectWeightAndReason(performance,weightRow)
    if isnan(performance), weight=NaN; reason=""; binName=""; return; end
    if performance >= 0
        if performance < 1, weight=weightRow.W_Pos_lt_1; reason=string(weightRow.Reason_Pos_lt_1); binName="Positive <1 dB";
        elseif performance <= 3, weight=weightRow.W_Pos_1_to_3; reason=string(weightRow.Reason_Pos_1_to_3); binName="Positive 1-3 dB";
        else, weight=weightRow.W_Pos_gt_3; reason=string(weightRow.Reason_Pos_gt_3); binName="Positive >3 dB"; end
    else
        absPerf = abs(performance);
        if absPerf < 1, weight=weightRow.W_Neg_lt_1; reason=string(weightRow.Reason_Neg_lt_1); binName="Negative <1 dB";
        elseif absPerf <= 3, weight=weightRow.W_Neg_1_to_3; reason=string(weightRow.Reason_Neg_1_to_3); binName="Negative 1-3 dB";
        else, weight=weightRow.W_Neg_gt_3; reason=string(weightRow.Reason_Neg_gt_3); binName="Negative >3 dB"; end
    end
end

function T = makeWeightedDetailRows(unitName,pol,label,metric,freq,perf,weight,value,reason,binName)
    T = table(); T.Unit = repmat(unitName,numel(freq),1); T.Polarization = repmat(pol,numel(freq),1); T.Label = repmat(label,numel(freq),1); T.Metric = repmat(metric,numel(freq),1);
    T.FrequencyGHz = freq; T.Performance = perf; T.SelectedWeight = weight; T.WeightedFOM = value; T.PerformanceBin = binName; T.Reason = reason;
end

function bandSummary = detectAllBandwidths(allResults)
    labels = unique(string(allResults.Label),'stable'); bandSummary = table();
    for i = 1:numel(labels)
        label = labels(i); T = allResults(string(allResults.Label)==label,:);
        bandSummary = [bandSummary; UnitPerfLib.detectBandwidthsFromMeasuredCurve(T.FrequencyGHz,T.MeasuredMedian,label,"Median"); UnitPerfLib.detectBandwidthsFromMeasuredCurve(T.FrequencyGHz,T.MeasuredPeak,label,"Peak")];
    end
end

function bandTbl = detectBandwidthsFromMeasuredCurve(freqGHz,measured,label,metricName)
    freqGHz=freqGHz(:); measured=measured(:); valid=~isnan(freqGHz)&~isnan(measured); freqGHz=freqGHz(valid); measured=measured(valid); bandTbl=table();
    if numel(freqGHz)<5, return; end
    y=smoothdata(measured,"movmean",2); minIdx=find(islocalmin(y)); maxIdx=find(islocalmax(y)); bandCount=0;
    for m=1:numel(minIdx)
        idxMin=minIdx(m); leftPeaks=maxIdx(maxIdx<idxMin); rightPeaks=maxIdx(maxIdx>idxMin);
        if isempty(leftPeaks)||isempty(rightPeaks), continue; end
        idxLeftPeak=leftPeaks(end); idxRightPeak=rightPeaks(1); avgPeak=mean([y(idxLeftPeak),y(idxRightPeak)]); threshold3dB=avgPeak-3;
        leftCross=UnitPerfLib.findCrossing(freqGHz(idxLeftPeak:idxMin),y(idxLeftPeak:idxMin),threshold3dB,"left");
        rightCross=UnitPerfLib.findCrossing(freqGHz(idxMin:idxRightPeak),y(idxMin:idxRightPeak),threshold3dB,"right");
        if isnan(leftCross)||isnan(rightCross), continue; end
        bandMask=freqGHz>=leftCross & freqGHz<=rightCross; if ~any(bandMask), continue; end
        [centerMeasured,localIdx]=min(measured(bandMask)); bandFreqs=freqGHz(bandMask); centerFreq=bandFreqs(localIdx); bandCount=bandCount+1;
        newRow=table(); newRow.Label=label; newRow.Metric=metricName; newRow.BandNumber=bandCount; newRow.CenterFrequencyGHz=centerFreq; newRow.BandwidthGHz=rightCross-leftCross;
        newRow.CenterMeasuredValue=centerMeasured; newRow.Left3dBFrequencyGHz=leftCross; newRow.Right3dBFrequencyGHz=rightCross; newRow.Threshold3dB=threshold3dB; newRow.AveragePeakMeasured=avgPeak;
        newRow.LeftPeakFrequencyGHz=freqGHz(idxLeftPeak); newRow.RightPeakFrequencyGHz=freqGHz(idxRightPeak); newRow.LeftPeakMeasured=measured(idxLeftPeak); newRow.RightPeakMeasured=measured(idxRightPeak);
        bandTbl=[bandTbl; newRow];
    end
end

function crossingFreq = findCrossing(freqGHz,y,threshold,side)
    crossingFreq=NaN;
    if side=="left"
        for k=numel(y):-1:2
            if (y(k-1)-threshold)*(y(k)-threshold)<=0, crossingFreq=interp1([y(k-1) y(k)],[freqGHz(k-1) freqGHz(k)],threshold); return; end
        end
    else
        for k=1:numel(y)-1
            if (y(k)-threshold)*(y(k+1)-threshold)<=0, crossingFreq=interp1([y(k) y(k+1)],[freqGHz(k) freqGHz(k+1)],threshold); return; end
        end
    end
end

function recTbl = buildRecommendationTable(allResults,summaryRows,selectedMask,selectedMetric,boiRanges,useBOI)
    selectedLabels=string(summaryRows.Label(selectedMask)); recTbl=table();
    for i=1:numel(selectedLabels)
        label=selectedLabels(i); T=allResults(string(allResults.Label)==label,:);
        if useBOI && ~isempty(boiRanges), T=T(UnitPerfLib.isFrequencyInBands(T.FrequencyGHz,boiRanges),:); end
        if isempty(T), continue; end
        if selectedMetric=="Median", values=T.ValueMedian; performance=T.PerformanceMedian; reasons=T.ReasonMedian; bins=T.BinMedian;
        else, values=T.ValuePeak; performance=T.PerformancePeak; reasons=T.ReasonPeak; bins=T.BinPeak; end
        passMask=performance>=0; failMask=performance<0; [worstContribution,worstIdx]=min(values,[],"omitnan");
        newRow=table(); newRow.Label=label; newRow.TotalWeightedFOM=sum(values,"omitnan"); newRow.AveragePerformance=mean(performance,"omitnan"); newRow.MinimumPerformance=min(performance,[],"omitnan");
        newRow.NumPassFrequencies=sum(passMask); newRow.NumFailFrequencies=sum(failMask); newRow.PassFrequencies=UnitPerfLib.formatFrequencyList(T.FrequencyGHz(passMask),12); newRow.FailFrequencies=UnitPerfLib.formatFrequencyList(T.FrequencyGHz(failMask),12);
        newRow.WorstFrequencyGHz=T.FrequencyGHz(worstIdx); newRow.WorstPerformance=performance(worstIdx); newRow.WorstWeightedContribution=worstContribution; newRow.WorstBin=bins(worstIdx); newRow.WorstReason=reasons(worstIdx);
        recTbl=[recTbl; newRow];
    end
    if ~isempty(recTbl), recTbl=sortrows(recTbl,"TotalWeightedFOM","descend"); end
end

function txt = buildRecommendationText(bestRow,recTbl,selectedMetric,boiRanges,useBOI)
    txt=strings(0); if useBOI && ~isempty(boiRanges), bandText=UnitPerfLib.bandRangesToText(boiRanges); else, bandText="all available frequencies"; end
    txt(end+1)="Recommended unit for "+selectedMetric+": "+string(bestRow.Label); txt(end+1)="Analysis band: "+bandText; txt(end+1)="";
    txt(end+1)="Why this unit is recommended:"; txt(end+1)="- It has the highest total weighted FOM among the selected units within the analysis band.";
    txt(end+1)="- Total weighted FOM: "+sprintf("%.3f",bestRow.TotalWeightedFOM); txt(end+1)="- Average performance margin: "+sprintf("%.3f dB",bestRow.AveragePerformance);
    txt(end+1)="- Worst performance margin: "+sprintf("%.3f dB at %.2f GHz",bestRow.WorstPerformance,bestRow.WorstFrequencyGHz);
    txt(end+1)="- Passing frequency points: "+string(bestRow.NumPassFrequencies); txt(end+1)="- Passing frequencies: "+string(bestRow.PassFrequencies);
    txt(end+1)="- Failing frequency points: "+string(bestRow.NumFailFrequencies); txt(end+1)="- Failing frequencies: "+string(bestRow.FailFrequencies); txt(end+1)="";
    txt(end+1)="Most important concern:"; txt(end+1)="- Frequency: "+sprintf("%.2f GHz",bestRow.WorstFrequencyGHz); txt(end+1)="- Performance: "+sprintf("%.3f dB",bestRow.WorstPerformance);
    txt(end+1)="- Weighted contribution: "+sprintf("%.3f",bestRow.WorstWeightedContribution); txt(end+1)="- Bin: "+string(bestRow.WorstBin); txt(end+1)="- Reason: "+string(bestRow.WorstReason);
    if height(recTbl)>1
        secondRow=recTbl(2,:); delta=bestRow.TotalWeightedFOM-secondRow.TotalWeightedFOM; txt(end+1)=""; txt(end+1)="Comparison with next best:";
        txt(end+1)="- Next best unit: "+string(secondRow.Label); txt(end+1)="- Weighted FOM advantage: "+sprintf("%.3f",delta);
        txt(end+1)="- Next best worst frequency: "+sprintf("%.2f GHz",secondRow.WorstFrequencyGHz); txt(end+1)="- Next best worst performance: "+sprintf("%.3f dB",secondRow.WorstPerformance);
    end
end

function txt = formatFrequencyList(freqs,maxCount)
    freqs=freqs(:); if isempty(freqs), txt="None"; return; end
    freqs=round(freqs,3);
    if numel(freqs)<=maxCount, txt=strjoin(string(freqs'),", ")+" GHz";
    else, shown=freqs(1:maxCount); txt=strjoin(string(shown'),", ")+" GHz, ... +"+string(numel(freqs)-maxCount)+" more"; end
end

function ranges = parseBandInterestString(str)
    str=strtrim(string(str)); ranges=zeros(0,2); if str=="", return; end
    parts=split(str,",");
    for i=1:numel(parts)
        token=strtrim(parts(i));
        if contains(token,"-")
            nums=split(token,"-"); if numel(nums)==2, a=str2double(strtrim(nums(1))); b=str2double(strtrim(nums(2))); if ~isnan(a)&&~isnan(b), ranges(end+1,:)=sort([a b]); end, end
        else
            c=str2double(token); if ~isnan(c), ranges(end+1,:)=[c c]; end
        end
    end
end

function mask = isFrequencyInBands(freq,ranges)
    freq=freq(:); mask=false(size(freq)); if isempty(ranges), mask(:)=true; return; end
    for i=1:size(ranges,1), mask=mask | (freq>=ranges(i,1) & freq<=ranges(i,2)); end
end

function txt = bandRangesToText(ranges)
    if isempty(ranges), txt="all available frequencies"; return; end
    parts=strings(size(ranges,1),1); for i=1:size(ranges,1), parts(i)=sprintf("%.2f-%.2f GHz",ranges(i,1),ranges(i,2)); end
    txt=strjoin(parts,", ");
end

function shadeBOI(ax,boiRanges,useBOI)
    if ~useBOI || isempty(boiRanges), return; end
    yl=ylim(ax); for i=1:size(boiRanges,1), xregion(ax,boiRanges(i,1),boiRanges(i,2),'FaceAlpha',0.05,'HandleVisibility','off'); end; ylim(ax,yl);
end

function T = reorderBandwidthTable(T)
    if isempty(T), return; end
    preferredOrder=["Label","Metric","BandNumber","CenterFrequencyGHz","BandwidthGHz","CenterMeasuredValue","Left3dBFrequencyGHz","Right3dBFrequencyGHz","Threshold3dB","AveragePeakMeasured","LeftPeakFrequencyGHz","RightPeakFrequencyGHz","LeftPeakMeasured","RightPeakMeasured"];
    varNames=string(T.Properties.VariableNames); existingOrder=preferredOrder(ismember(preferredOrder,varNames)); remainingOrder=varNames(~ismember(varNames,existingOrder)); finalOrder=[existingOrder(:)' remainingOrder(:)']; T=T(:,finalOrder);
end

function plotBandwidthAxis(ax,allResults,bandSummary,selectedLabels,selectedMetric,boiRanges,useBOI,showBands,showCenter,show3dB,annotateText)
    cla(ax); hold(ax,"on");
    for kk=1:numel(selectedLabels)
        idx=string(allResults.Label)==selectedLabels(kk); f=allResults.FrequencyGHz(idx); if selectedMetric=="Median", y=allResults.MeasuredMedian(idx); else, y=allResults.MeasuredPeak(idx); end
        plot(ax,f,y,'DisplayName',selectedLabels(kk)+" "+selectedMetric,'LineWidth',1.25);
        thisBand=bandSummary(string(bandSummary.Label)==selectedLabels(kk) & string(bandSummary.Metric)==selectedMetric,:);
        if useBOI && ~isempty(boiRanges), thisBand=thisBand(UnitPerfLib.isFrequencyInBands(thisBand.CenterFrequencyGHz,boiRanges),:); end
        for b=1:height(thisBand)
            xL=thisBand.Left3dBFrequencyGHz(b); xR=thisBand.Right3dBFrequencyGHz(b); xC=thisBand.CenterFrequencyGHz(b); yC=thisBand.CenterMeasuredValue(b); bw=thisBand.BandwidthGHz(b);
            if showBands, xregion(ax,xL,xR,'FaceAlpha',0.08,'HandleVisibility','off'); end
            if show3dB, xline(ax,xL,'k:','HandleVisibility','off'); xline(ax,xR,'k:','HandleVisibility','off'); end
            if showCenter, plot(ax,xC,yC,'ko','MarkerFaceColor','k','HandleVisibility','off'); if annotateText, text(ax,xC,yC,sprintf("CF %.2f GHz\nBW %.2f GHz",xC,bw),'FontSize',9,'VerticalAlignment','bottom','HorizontalAlignment','center'); end, end
        end
    end
    UnitPerfLib.shadeBOI(ax,boiRanges,useBOI); xlabel(ax,"Frequency GHz"); ylabel(ax,"Measured "+selectedMetric); title(ax,"Measured "+selectedMetric+" vs Frequency with Bandwidths"); legend(ax,'Location','best'); grid(ax,"on"); hold(ax,"off");
end

function openPolarHeatmapViewer(patternDB)
    labels=string({patternDB.Label}); oldFig=findall(groot,'Tag','PolarHeatmapViewer'); delete(oldFig);
    figHeat=uifigure('Name','Polar Heatmap Viewer','Position',[100 100 950 760],'Tag','PolarHeatmapViewer');
    grid=uigridlayout(figHeat,[2 1]); grid.RowHeight={60,'1x'}; grid.Padding=[8 8 8 8];
    ctrlGrid=uigridlayout(grid,[1 5]); ctrlGrid.ColumnWidth={80,'1x',160,120,120};
    uilabel(ctrlGrid,'Text','Unit/Pol:'); unitDrop=uidropdown(ctrlGrid,'Items',labels,'Value',labels(1));
    normDrop=uidropdown(ctrlGrid,'Items',["Raw","Normalize each frequency","Normalize global max"],'Value',"Raw"); densityDrop=uidropdown(ctrlGrid,'Items',["Fast","Detailed"],'Value',"Fast"); refreshBtn=uibutton(ctrlGrid,'Text','Update'); ax=uiaxes(grid);
    refreshBtn.ButtonPushedFcn=@(src,event) updateHeatmap(); updateHeatmap();
    function updateHeatmap()
        if ~isvalid(figHeat), return; end; figHeat.Pointer='watch'; drawnow limitrate; cla(ax);
        selectedLabel=string(unitDrop.Value); idxDB=find(labels==selectedLabel,1); if isempty(idxDB), figHeat.Pointer='arrow'; return; end
        freqs=patternDB(idxDB).FrequencyGHz(:); anglesDeg=patternDB(idxDB).AnglesDeg(:); plotPattern=patternDB(idxDB).Pattern;
        switch normDrop.Value
            case "Normalize each frequency", plotPattern=plotPattern-max(plotPattern,[],1);
            case "Normalize global max", plotPattern=plotPattern-max(plotPattern(:));
        end
        if densityDrop.Value=="Fast"
            fIdx=unique(round(linspace(1,numel(freqs),min(80,numel(freqs))))); aIdx=unique(round(linspace(1,numel(anglesDeg),min(181,numel(anglesDeg)))));
            freqsPlot=freqs(fIdx); anglesPlot=anglesDeg(aIdx); plotPattern=plotPattern(aIdx,fIdx);
        else, freqsPlot=freqs; anglesPlot=anglesDeg; end
        hold(ax,"on");
        for fIdx=1:numel(freqsPlot)
            r=freqsPlot(fIdx)*ones(size(anglesPlot)); theta=deg2rad(anglesPlot); scatter(ax,r.*cos(theta),r.*sin(theta),14,plotPattern(:,fIdx),'filled','HandleVisibility','off');
        end
        colormap(ax,turbo); cb=colorbar(ax); cb.Label.String="Measured Value"; ringFreqs=linspace(min(freqsPlot),max(freqsPlot),5); thetaFine=linspace(deg2rad(min(anglesPlot)),deg2rad(max(anglesPlot)),720);
        for rr=ringFreqs, plot(ax,rr*cos(thetaFine),rr*sin(thetaFine),'k:','LineWidth',0.75,'HandleVisibility','off'); text(ax,rr*cos(deg2rad(max(anglesPlot))),rr*sin(deg2rad(max(anglesPlot))),sprintf("%.1f GHz",rr),'FontSize',9,'HorizontalAlignment','left'); end
        angleMin=min(anglesPlot); angleMax=max(anglesPlot); angleSpan=angleMax-angleMin; if angleSpan>=300, angleTicks=-180:45:180; elseif angleSpan>=180, angleTicks=angleMin:30:angleMax; else, angleTicks=angleMin:15:angleMax; end
        angleTicks=angleTicks(angleTicks>=angleMin & angleTicks<=angleMax);
        for aa=angleTicks, theta=deg2rad(aa); plot(ax,[min(freqsPlot) max(freqsPlot)]*cos(theta),[min(freqsPlot) max(freqsPlot)]*sin(theta),'k:','LineWidth',0.75,'HandleVisibility','off'); text(ax,1.06*max(freqsPlot)*cos(theta),1.06*max(freqsPlot)*sin(theta),sprintf("%.0f°",aa),'FontSize',9,'HorizontalAlignment','center'); end
        axis(ax,'equal'); margin=1.15*max(freqsPlot); xlim(ax,[-margin margin]); ylim(ax,[-margin margin]); ax.XTick=[]; ax.YTick=[]; ax.Box='off'; title(ax,"Polar Frequency-Angle Heatmap: "+selectedLabel); hold(ax,"off"); if isvalid(figHeat), figHeat.Pointer='arrow'; end; drawnow limitrate;
    end
end
end
end
