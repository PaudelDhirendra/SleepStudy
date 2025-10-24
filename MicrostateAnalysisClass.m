classdef MicrostateAnalysisClass < handle
    % Enhanced MicrostateAnalysisClass: Comprehensive EEG microstate analysis pipeline
    % Now includes sleep stage-specific analysis and comprehensive reporting

    properties
        edfLoader
        fs
        channelLabels
        data
        microstateParams
        microstateResults
        edfPath
        xmlPath
        mappedChannelNames
        artifactDetector
        cleaningSummary
        originalData
        originalChannelLabels
        allChannelData
        allChannelLabels

        % New properties for comprehensive analysis
        numericHypnogram
        stage2Mask
        stage3Mask
        sleepCycles
        microstateTemplates
        transitionMatrices
        clinicalScores
    end

    methods
        function obj = MicrostateAnalysisClass(edfFile, xmlFile, params)
            if nargin < 3
                params = struct();
            end
            obj.edfPath = edfFile;
            obj.xmlPath = xmlFile;

            % ✅ CHECK IF CHANNELS ARE ALREADY PROVIDED
            if isfield(params, 'edfLoader') && isfield(params, 'allChannelData')
                fprintf('Using pre-loaded EDF data from GUI...\n');
                obj.edfLoader = params.edfLoader;
                obj.channelLabels = params.allChannelLabels;
                obj.data = params.allChannelData;
                obj.fs = params.fs;
                obj.mappedChannelNames = params.allChannelLabels;

                % Store ALL original data
                obj.allChannelData = params.allChannelData;
                obj.allChannelLabels = params.allChannelLabels;

            else
                % Fallback to original loading
                try
                    fprintf('Loading EDF file: %s\n', edfFile);
                    obj.edfLoader = BlockEdfLoadClass(edfFile);
                    obj.edfLoader.numCompToLoad = 3;
                    obj.edfLoader.SWAP_MIN_MAX = 1;
                    obj.edfLoader = obj.edfLoader.blockEdfLoad;
                catch ME
                    error('Error loading EDF file with BlockEdfLoadClass: %s', ME.message);
                end
            end

            % Load hypnogram if available
            obj.loadHypnogram();

            % Only setup channels if not already provided
            if ~isfield(params, 'allChannelLabels')
                obj.setupMappedChannels();
            end

            % Store ALL channels including ECG for cleaning phase
            obj.allChannelData = obj.data;
            obj.allChannelLabels = obj.channelLabels;

            obj.setDefaultParams(params);
            obj.microstateResults = [];
            obj.artifactDetector = ArtifactDetectionClass();
        end

        function runAnalysis(obj, sleepStages, sleepCycles)
            % Enhanced analysis with SLEEP-ONLY global analysis
            fprintf('Starting comprehensive microstate analysis (SLEEP-ONLY global)...\n');

            % Set defaults: Global = TST only, Stage analysis = includes WASO
            if nargin < 2 || isempty(sleepStages)
                globalStages = [1, 2, 3, 5];  % TST ONLY: N1, N2, N3, REM
                stageAnalysisStages = [0, 1, 2, 3, 5];  % INCLUDES WASO: Wake, N1, N2, N3, REM
            else
                globalStages = sleepStages(sleepStages > 0);  % Remove wake for global
                stageAnalysisStages = sleepStages;  % Keep wake for stage analysis
            end

            if nargin < 3
                sleepCycles = [];
            end

            fprintf('Analysis parameters:\n');
            fprintf('  Global analysis (TST): %s\n', mat2str(globalStages));
            fprintf('  Stage analysis (includes WASO): %s\n', mat2str(stageAnalysisStages));

            % Detect sleep cycles if needed
            if isempty(sleepCycles) && ~isempty(obj.numericHypnogram)
                fprintf('Detecting sleep cycles...\n');
                obj.detectSleepCycles();
                sleepCycles = obj.sleepCycles;
            elseif ~isempty(sleepCycles)
                obj.sleepCycles = sleepCycles;
            end

            fprintf('Analysis parameters:\n');
            fprintf('  Sleep stages: %s\n', mat2str(sleepStages));
            if ~isempty(sleepCycles)
                nCycles = length(unique(sleepCycles(sleepCycles > 0)));
                fprintf('  Sleep cycles: %d cycles\n', nCycles);
            else
                fprintf('  Sleep cycles: Not available\n');
            end

            % Data cleaning (existing code)
            targetChannels = obj.microstateParams.preferredChannels;
            microstateIndices = [];
            microstateLabels = {};

            for i = 1:length(targetChannels)
                idx = find(strcmp(obj.allChannelLabels, targetChannels{i}));
                if ~isempty(idx)
                    microstateIndices(end+1) = idx(1);
                    microstateLabels{end+1} = targetChannels{i};
                end
            end

            if isempty(microstateIndices)
                error('No suitable EEG channels found for microstate analysis.');
            end

            % Perform targeted cleaning
            [cleanData, artifactInfo] = obj.performTargetedCleaning(microstateIndices, microstateLabels);

            % Extract microstate channels from cleaned data
            obj.data = cell(1, length(microstateIndices));
            for i = 1:length(microstateIndices)
                obj.data{i} = cleanData{i};
            end
            obj.channelLabels = microstateLabels;

            obj.cleaningSummary = obj.artifactDetector.getCleaningSummary();

            % Main microstate analysis
            fprintf('Starting comprehensive microstate analysis on %d channels...\n', length(obj.data));

            % Convert to matrix format
            dataMatrix = zeros(length(obj.data), length(obj.data{1}));
            for i = 1:length(obj.data)
                dataMatrix(i, :) = obj.data{i};
            end

            % ✅ OPTIMIZED: Perform GLOBAL preprocessing ONCE
            fprintf('Performing global preprocessing (one-time)...\n');
            [globalDataProc, fsNew] = obj.preprocessData(dataMatrix, obj.fs);

            % ✅ OPTIMIZED: Create global artifact mask
            globalArtifactMask = any(isnan(globalDataProc), 1);
            fprintf('Global artifact mask: %.1f%% clean data\n', (1 - mean(globalArtifactMask)) * 100);

            % ✅ GLOBAL: Create TST-only mask (sleep stages only)
            if ~isempty(obj.numericHypnogram)
                tstMask = obj.createSleepOnlyMask(size(globalDataProc, 2));
                fprintf('TST-only analysis: %.1f%% of recording is sleep\n', mean(tstMask)*100);
            else
                tstMask = true(1, size(globalDataProc, 2));
                fprintf('No hypnogram - using entire recording for global analysis\n');
            end

            % ✅ PERFORM TST-ONLY GLOBAL MICROSTATE ANALYSIS
            tstGlobalData = globalDataProc(:, tstMask & ~globalArtifactMask);
            fprintf('TST-global analysis: %d clean samples (%.1f hours)\n', ...
                size(tstGlobalData, 2), size(tstGlobalData, 2)/fsNew/3600);

            tstGlobalResults = obj.performMicrostateAnalysisOptimized(tstGlobalData, fsNew);



            % ✅ STAGE ANALYSIS: Includes WASO as a separate stage
            stageResults = struct();
            if ~isempty(obj.numericHypnogram) && ~isempty(stageAnalysisStages)
                fprintf('Performing sleep stage analysis (including WASO)...\n');
                stageResults = obj.performSleepStageAnalysisOptimized(globalDataProc, fsNew, stageAnalysisStages, globalArtifactMask);
            end

            % ✅ OPTIMIZED: Sleep cycle analysis - reuse preprocessed data
            cycleResults = struct();
            if ~isempty(sleepCycles)
                fprintf('Performing sleep cycle analysis (using preprocessed data)...\n');
                cycleResults = obj.performSleepCycleAnalysisOptimized(globalDataProc, fsNew, sleepCycles, globalArtifactMask);
            end

            % ✅ CALCULATE SLEEP STATISTICS
            sleepStats = obj.calculateSleepStatistics(globalArtifactMask);

            % Transition probability analysis (on TST-global data)
            transitionResults = obj.calculateTransitionProbabilities(tstGlobalResults.segmentation, tstGlobalResults.numMaps);

            % Store comprehensive results
            obj.microstateResults = struct(...
                'sleepGlobal', tstGlobalResults, ...      % TST-only global analysis
                'stageSpecific', stageResults, ...        % Includes WASO as stage
                'cycleSpecific', cycleResults, ...
                'sleepStatistics', sleepStats, ...        % TST, WASO, stage statistics
                'transitions', transitionResults, ...
                'cleaningSummary', obj.cleaningSummary, ...
                'parameters', obj.microstateParams ...
                );

            fprintf('Comprehensive microstate analysis completed successfully\n');
            obj.printSummaryStatistics();
        end

        % SAVE TO .MAT FILE
        function saveResults(obj, outputFile)
            if isempty(obj.microstateResults)
                warning('No results to save.');
                return;
            end
            microstateResults = obj.microstateResults;
            save(outputFile, 'microstateResults');
            fprintf('Saved microstate results to: %s\n', outputFile);
        end

        % SAVE TO EXCEL FILE - Enhanced version with comprehensive results
        function saveResultsToExcel(obj, outputFile)
            if isempty(obj.microstateResults)
                warning('No results to save.');
                return;
            end

            fprintf('Saving comprehensive microstate results to Excel...\n');

            R = obj.microstateResults;

            %% 1. SLEEP-GLOBAL MICROSTATE STATISTICS
            globalStats = {
                'Number_of_Maps', R.sleepGlobal.numMaps;
                'Total_GEV', R.sleepGlobal.totalGEV;
                'Sampling_Rate_Hz', R.sleepGlobal.fs;
                'Number_of_Channels', length(R.sleepGlobal.channelLabels);
                'Number_of_GFP_Peaks', length(R.sleepGlobal.gfpPeaks);
                'Analysis_Duration_s', size(R.sleepGlobal.segmentation, 2) / R.sleepGlobal.fs;
                'Global_Mean_Duration_ms', R.sleepGlobal.meanDuration * 1000;
                'Global_Mean_Occurrence_Hz', R.sleepGlobal.meanOccurrence;
                'Normalized_Entropy', R.sleepGlobal.entropy;
                };

            % Add map-specific statistics
            for i = 1:R.sleepGlobal.numMaps
                globalStats{end+1, 1} = sprintf('Map_%d_GEV', i);
                globalStats{end, 2} = R.sleepGlobal.mapGEV(i);

                globalStats{end+1, 1} = sprintf('Map_%d_Mean_Duration_ms', i);
                globalStats{end, 2} = R.sleepGlobal.mapDuration(i) * 1000;

                globalStats{end+1, 1} = sprintf('Map_%d_Occurrence_Hz', i);
                globalStats{end, 2} = R.sleepGlobal.mapOccurrence(i);

                globalStats{end+1, 1} = sprintf('Map_%d_Coverage_Percent', i);
                globalStats{end, 2} = R.sleepGlobal.mapCoverage(i) * 100;
            end

            globalTable = cell2table(globalStats, 'VariableNames', {'Parameter', 'Value'});

            %% 2. INDIVIDUAL MICROSTATE MAPS
            mapTable = array2table(R.sleepGlobal.templates, ...
                'VariableNames', arrayfun(@(x) sprintf('Map_%d', x), 1:R.sleepGlobal.numMaps, 'UniformOutput', false));
            mapTable.Channel = R.sleepGlobal.channelLabels';

            %% 3. TRANSITION PROBABILITIES
            transData = {};
            for i = 1:R.sleepGlobal.numMaps
                for j = 1:R.sleepGlobal.numMaps
                    transData{end+1, 1} = sprintf('Map_%d_to_%d', i, j);
                    transData{end, 2} = R.transitions.observed(i, j);
                    transData{end, 3} = R.transitions.expected(i, j);
                    transData{end, 4} = R.transitions.difference(i, j);
                end
            end
            transTable = cell2table(transData, 'VariableNames', {'Transition', 'Observed_Probability', 'Expected_Probability', 'Difference'});

            %% 4. SLEEP STAGE STATISTICS (if available)
           %% 4. SLEEP STAGE STATISTICS (if available)
stageTable = table();
if isfield(R, 'stageSpecific') && ~isempty(fieldnames(R.stageSpecific))
    stages = fieldnames(R.stageSpecific);
    stageData = {};
    
    for s = 1:length(stages)
        stageName = stages{s};
        stageResult = R.stageSpecific.(stageName);
        
        % Only include if stageResult is not empty and has expected fields
        if ~isempty(stageResult) && isfield(stageResult, 'totalGEV') && stageResult.numMaps > 0
            stageData{end+1, 1} = stageName;
            stageData{end, 2} = stageResult.totalGEV;
            stageData{end, 3} = stageResult.meanDuration * 1000;
            stageData{end, 4} = stageResult.meanOccurrence;
            stageData{end, 5} = stageResult.entropy;  % ✅ ADD ENTROPY (now column 5)
            
            % FIX: Handle variable number of maps in stage results
            % Start from column 6 for map coverage
            for i = 1:stageResult.numMaps
                if i <= length(stageResult.mapCoverage)
                    stageData{end, 5+i} = stageResult.mapCoverage(i) * 100; % Now 5+i
                else
                    stageData{end, 5+i} = NaN;
                end
            end
            
            % Fill remaining columns if stage has fewer maps than global
            if stageResult.numMaps < R.sleepGlobal.numMaps
                for i = (stageResult.numMaps+1):R.sleepGlobal.numMaps
                    stageData{end, 5+i} = NaN; % Now 5+i
                end
            end
        end
    end
    
    if ~isempty(stageData)
        varNames = {'Stage', 'Total_GEV', 'Mean_Duration_ms', 'Mean_Occurrence_Hz', 'Entropy'}; % ✅ ADDED ENTROPY
        
        % Add map coverage columns - FIXED: Add correct number of columns
        for i = 1:R.sleepGlobal.numMaps
            varNames{end+1} = sprintf('Map_%d_Coverage_Percent', i);
        end
        
        % ✅ CRITICAL FIX: Ensure we have the right number of columns
        if size(stageData, 2) > length(varNames)
            % Truncate extra columns
            stageData = stageData(:, 1:length(varNames));
        elseif size(stageData, 2) < length(varNames)
            % Pad with empty cells
            for row = 1:size(stageData, 1)
                for col = (size(stageData, 2)+1):length(varNames)
                    stageData{row, col} = NaN;
                end
            end
        end
        
        stageTable = cell2table(stageData, 'VariableNames', varNames);
    end
end

            %% 5. SLEEP CYCLE STATISTICS (if available)
           %% 5. SLEEP CYCLE STATISTICS (if available)
cycleTable = table();
if isfield(R, 'cycleSpecific') && ~isempty(fieldnames(R.cycleSpecific))
    cycles = fieldnames(R.cycleSpecific);
    cycleData = {};
    
    for c = 1:length(cycles)
        cycleName = cycles{c};
        cycleResult = R.cycleSpecific.(cycleName);
        
        % Only include if cycleResult is not empty and has expected fields
        if ~isempty(cycleResult) && isfield(cycleResult, 'totalGEV') && cycleResult.numMaps > 0
            cycleData{end+1, 1} = cycleName;
            cycleData{end, 2} = cycleResult.totalGEV;
            cycleData{end, 3} = cycleResult.meanDuration * 1000;
            cycleData{end, 4} = cycleResult.meanOccurrence;
            cycleData{end, 5} = cycleResult.entropy;  % ✅ ADD ENTROPY (now column 5)
            
            % FIX: Handle variable number of maps in cycle results
            % Start from column 6 for map coverage
            for i = 1:cycleResult.numMaps
                if i <= length(cycleResult.mapCoverage)
                    cycleData{end, 5+i} = cycleResult.mapCoverage(i) * 100; % Now 5+i
                else
                    cycleData{end, 5+i} = NaN;
                end
            end
            
            % Fill remaining columns if cycle has fewer maps than global
            if cycleResult.numMaps < R.sleepGlobal.numMaps
                for i = (cycleResult.numMaps+1):R.sleepGlobal.numMaps
                    cycleData{end, 5+i} = NaN; % Now 5+i
                end
            end
        end
    end
    
    if ~isempty(cycleData)
        varNames = {'Cycle', 'Total_GEV', 'Mean_Duration_ms', 'Mean_Occurrence_Hz', 'Entropy'}; % ✅ ADDED ENTROPY
        
        % Add map coverage columns - FIXED: Add correct number of columns
        for i = 1:R.sleepGlobal.numMaps
            varNames{end+1} = sprintf('Map_%d_Coverage_Percent', i);
        end
        
        % ✅ CRITICAL FIX: Ensure we have the right number of columns
        if size(cycleData, 2) > length(varNames)
            % Truncate extra columns
            cycleData = cycleData(:, 1:length(varNames));
        elseif size(cycleData, 2) < length(varNames)
            % Pad with empty cells
            for row = 1:size(cycleData, 1)
                for col = (size(cycleData, 2)+1):length(varNames)
                    cycleData{row, col} = NaN;
                end
            end
        end
        
        cycleTable = cell2table(cycleData, 'VariableNames', varNames);
    end
end

            %% 6. DATA QUALITY METRICS
            qualityStats = {
                'Total_Recording_Time_min', length(obj.data{1}) / obj.fs(1) / 60;
                'Sleep_Only_Analysis_Time_min', size(R.sleepGlobal.segmentation, 2) / R.sleepGlobal.fs / 60;
                'Artifact_Free_Percent', obj.cleaningSummary.cleanDataPercentage;
                'Artifact_Percent', obj.cleaningSummary.artifactPercentage;
                'ECG_Decontamination_Applied', obj.cleaningSummary.ecgDecontaminationApplied;
                'Total_Artifacts', obj.cleaningSummary.totalArtifacts;
                };
            qualityTable = cell2table(qualityStats, 'VariableNames', {'Parameter', 'Value'});

            %% 7. GFP PEAKS TABLE
            maxPeaksToSave = min(1000, length(R.sleepGlobal.gfpPeaks));
            gfpTable = table((1:maxPeaksToSave)', R.sleepGlobal.gfpPeaks(1:maxPeaksToSave)', ...
                'VariableNames', {'Peak_Index', 'Sample_Index'});

            %% 8. WRITE ALL SHEETS TO EXCEL
            writetable(globalTable, outputFile, 'Sheet', 'Sleep_Global_Statistics');
            writetable(mapTable, outputFile, 'Sheet', 'Microstate_Maps');
            writetable(transTable, outputFile, 'Sheet', 'Transition_Probabilities');

            if ~isempty(stageTable) && height(stageTable) > 0
                writetable(stageTable, outputFile, 'Sheet', 'Stage_Statistics');
            end

            if ~isempty(cycleTable) && height(cycleTable) > 0
                writetable(cycleTable, outputFile, 'Sheet', 'Cycle_Statistics');
            end

            writetable(qualityTable, outputFile, 'Sheet', 'Data_Quality');
            writetable(gfpTable, outputFile, 'Sheet', 'GFP_Peaks');

            fprintf('SUCCESS: Saved comprehensive microstate results to: %s\n', outputFile);
            fprintf('Sheets created:\n');
            fprintf('  - Sleep_Global_Statistics: Sleep-only summary metrics\n');
            fprintf('  - Microstate_Maps: Template maps for each microstate\n');
            fprintf('  - Transition_Probabilities: Microstate transition analysis\n');
            if ~isempty(stageTable) && height(stageTable) > 0
                fprintf('  - Stage_Statistics: Sleep stage-specific analysis\n');
            end
            if ~isempty(cycleTable) && height(cycleTable) > 0
                fprintf('  - Cycle_Statistics: Sleep cycle-specific analysis\n');
            end
            fprintf('  - Data_Quality: Recording quality metrics\n');
            fprintf('  - GFP_Peaks: GFP peak locations\n');

            %% 9. SLEEP STATISTICS TABLE
            if isfield(R, 'sleepStatistics') && ~isempty(R.sleepStatistics)
                stats = R.sleepStatistics;
                sleepData = {
                    'Total_Recording_Epochs', stats.totalRecordingEpochs;
                    'Total_Clean_Epochs', stats.totalCleanEpochs;
                    'Artifact_Contaminated_Epochs', stats.artifactContaminatedEpochs;
                    'Data_Quality_Percent', stats.dataQualityPercent;
                    'Total_Sleep_Time_Minutes', stats.TST_minutes;
                    'WASO_Minutes', stats.WASO_minutes;
                    'Sleep_Period_Time_Minutes', stats.SPT_minutes;
                    'N1_Minutes', stats.N1_minutes;
                    'N2_Minutes', stats.N2_minutes;
                    'N3_Minutes', stats.N3_minutes;
                    'REM_Minutes', stats.REM_minutes;
                    'N1_Percent', stats.N1_percent;
                    'N2_Percent', stats.N2_percent;
                    'N3_Percent', stats.N3_percent;
                    'REM_Percent', stats.REM_percent;
                    };
                sleepTable = cell2table(sleepData, 'VariableNames', {'Parameter', 'Value'});

                writetable(sleepTable, outputFile, 'Sheet', 'Sleep_Statistics');
                fprintf('  - Sleep_Statistics: Artifact-corrected sleep architecture\n');
            end
            %% 10. ENTROPY AND ADVANCED METRICS
            if isfield(R.sleepGlobal, 'entropy')
                entropyData = {
                    'Normalized_Entropy', R.sleepGlobal.entropy;
                    };
                entropyTable = cell2table(entropyData, 'VariableNames', {'Parameter', 'Value'});
                writetable(entropyTable, outputFile, 'Sheet', 'Entropy');
                fprintf('  - Entropy: Microstate complexity (0-1 scale)\n');
            end
        end

    end

    methods (Access = private)
        function loadHypnogram(obj)
            % Load hypnogram similar to SpindleDetectionClass - FIXED VERSION
            try
                if isempty(obj.xmlPath) || ~exist(obj.xmlPath, 'file')
                    fprintf('No XML file provided for hypnogram.\n');
                    obj.numericHypnogram = [];
                    return;
                end

                fprintf('Loading hypnogram: %s\n', obj.xmlPath);

                % Use the EXACT SAME approach as SpindleDetectionClass
                lcaObj = loadCompumedicsAnnotationsClass(obj.xmlPath);
                lcaObj.scoreKey = { ...
                    {'Awake', 0, 'W'}; {'1', 1, '1'}; {'2', 2, '2'}; ...
                    {'3', 3, '3'}; {'4', 4, '4'}; {'REM', 5, 'R'}; ...
                    {'X', 9, 'X'}; {'X', 10, 'X'}};
                lcaObj.GET_SCORED_EVENTS = 0;
                lcaObj = lcaObj.loadFile;

                obj.numericHypnogram = lcaObj.numericHypnogram;
                obj.stage2Mask = obj.numericHypnogram == 2;
                obj.stage3Mask = obj.numericHypnogram == 3;

                fprintf('Hypnogram loaded: %d epochs\n', length(obj.numericHypnogram));

                % Debug: Print stage distribution
                if ~isempty(obj.numericHypnogram)
                    stages = unique(obj.numericHypnogram);
                    fprintf('Stage distribution:\n');
                    for i = 1:length(stages)
                        stage = stages(i);
                        count = sum(obj.numericHypnogram == stage);
                        stageName = obj.getStageName(stage);
                        fprintf('  %s (%d): %d epochs (%.1f%%)\n', stageName, stage, count, count/length(obj.numericHypnogram)*100);
                    end
                end

            catch ME
                warning('Hypnogram loading failed: %s', ME.message);
                fprintf('Trying alternative hypnogram loading method...\n');

                % Alternative approach if the first method fails
                try
                    % Try direct loading without the class
                    % This is a fallback - adjust based on your actual hypnogram format
                    obj.numericHypnogram = [];
                catch ME2
                    fprintf('Alternative hypnogram loading also failed: %s\n', ME2.message);
                    obj.numericHypnogram = [];
                end
            end
        end

        function detectSleepCycles(obj)
            % FIXED: Proper sleep cycle detection with correct epoch mapping
            if isempty(obj.numericHypnogram)
                fprintf('No hypnogram available for sleep cycle detection\n');
                obj.sleepCycles = [];
                return;
            end

            fprintf('Detecting sleep cycles...\n');

            try
                % Create NREM-only hypnogram for cycle detection
                nrem_hypnogram = obj.numericHypnogram;

                % Set wake and REM to 0, keep NREM stages as is
                nrem_hypnogram(nrem_hypnogram == 0 | nrem_hypnogram == 1 | nrem_hypnogram == 5) = 0;

                % Use sleep_cycles function
                if exist('sleep_cycles', 'file') == 2
                    fprintf('Using sleep_cycles function for cycle detection\n');
                    detected_cycles = sleep_cycles(nrem_hypnogram, 'Visible', false);
                else
                    fprintf('sleep_cycles function not found, cannot detect sleep cycles\n');
                    detected_cycles = zeros(size(nrem_hypnogram));
                end

                % ✅ CRITICAL FIX: Ensure detected_cycles matches hypnogram length
                if length(detected_cycles) ~= length(obj.numericHypnogram)
                    fprintf('Warning: Adjusting cycle length from %d to %d\n', ...
                        length(detected_cycles), length(obj.numericHypnogram));

                    if length(detected_cycles) < length(obj.numericHypnogram)
                        % Pad with zeros at the end
                        detected_cycles(end+1:length(obj.numericHypnogram)) = 0;
                    else
                        % Truncate to match hypnogram
                        detected_cycles = detected_cycles(1:length(obj.numericHypnogram));
                    end
                end

                obj.sleepCycles = detected_cycles;

                nCycles = length(unique(obj.sleepCycles(obj.sleepCycles > 0)));
                fprintf('Detected %d sleep cycles\n', nCycles);

                % Debug: Print cycle distribution
                cycles = unique(obj.sleepCycles(obj.sleepCycles > 0));
                for i = 1:length(cycles)
                    cycle = cycles(i);
                    epochs = find(obj.sleepCycles == cycle);
                    if ~isempty(epochs)
                        fprintf('  Cycle %d: %d epochs (epochs %d to %d, %.1f min)\n', ...
                            cycle, length(epochs), min(epochs), max(epochs), length(epochs) * 0.5);
                    end
                end

            catch ME
                fprintf('Sleep cycle detection failed: %s\n', ME.message);
                obj.sleepCycles = [];
            end
        end



        function [cleanData, artifactInfo] = performTargetedCleaning(obj, microstateIndices, microstateLabels)
            % Targeted cleaning for microstate channels - consistent with spindle detection
            cleaningChannels = microstateIndices;
            cleaningLabels = microstateLabels;

            if obj.artifactDetector.denoiseEcg
                ecgIdx = obj.artifactDetector.findECGChannel(obj.allChannelLabels);
                if ~isempty(ecgIdx)
                    cleaningChannels(end+1) = ecgIdx;
                    cleaningLabels{end+1} = obj.allChannelLabels{ecgIdx};
                    fprintf('Including ECG channel for decontamination: %s\n', obj.allChannelLabels{ecgIdx});
                end
            end

            dataToClean = cell(1, length(cleaningChannels));
            labelsToClean = cell(1, length(cleaningChannels));
            for i = 1:length(cleaningChannels)
                dataToClean{i} = obj.allChannelData{cleaningChannels(i)};
                labelsToClean{i} = cleaningLabels{i};
            end

            % Use first channel's sampling rate for cleaning (assuming consistent within subject)
            cleaning_fs = obj.fs(1);

            [cleanData, artifactInfo] = obj.artifactDetector.fullDataCleaning(...
                dataToClean, labelsToClean, cleaning_fs, obj.numericHypnogram);

            % Extract only the microstate channels (exclude ECG channel from results)
            cleanData = cleanData(1:length(microstateIndices));
        end

        function sleepStats = calculateSleepStatistics(obj, globalArtifactMask)
            % Calculate comprehensive sleep statistics (artifact-corrected)
            if isempty(obj.numericHypnogram)
                sleepStats = [];
                return;
            end

            fprintf('Calculating artifact-corrected sleep statistics...\n');

            % Use first channel's sampling rate
            if length(obj.fs) >= 1
                fs_ref = obj.fs(1);
            else
                fs_ref = 256;
            end

            samplesPerEpoch = 30 * fs_ref;
            totalSamples = length(globalArtifactMask);
            totalEpochs = min(length(obj.numericHypnogram), ceil(totalSamples/samplesPerEpoch));

            % Initialize counters for each stage
            stages = [0, 1, 2, 3, 5]; % Wake, N1, N2, N3, REM
            stageCounts = zeros(size(stages));
            artifactCounts = zeros(size(stages));

            % Count epochs and artifacts per stage
            for epoch = 1:totalEpochs
                stage = obj.numericHypnogram(epoch);
                stageIdx = find(stages == stage, 1);

                if isempty(stageIdx)
                    continue; % Skip unknown stages
                end

                startSample = (epoch-1) * samplesPerEpoch + 1;
                endSample = min(epoch * samplesPerEpoch, totalSamples);
                epochArtifactMask = globalArtifactMask(startSample:endSample);

                stageCounts(stageIdx) = stageCounts(stageIdx) + 1;

                % Count artifact-contaminated epochs (>50% artifacts)
                if mean(epochArtifactMask) > 0.5
                    artifactCounts(stageIdx) = artifactCounts(stageIdx) + 1;
                end
            end

            % Calculate clean epochs
            cleanStageCounts = stageCounts - artifactCounts;

            % Calculate key metrics
            sleepStats = struct();

            % Basic counts
            sleepStats.totalRecordingEpochs = totalEpochs;
            sleepStats.totalCleanEpochs = sum(cleanStageCounts);
            sleepStats.artifactContaminatedEpochs = sum(artifactCounts);
            sleepStats.dataQualityPercent = (sleepStats.totalCleanEpochs / totalEpochs) * 100;

            % Sleep architecture metrics
            sleepStats.TST_minutes = sum(cleanStageCounts(2:5)) * 0.5; % N1+N2+N3+REM
            sleepStats.WASO_minutes = cleanStageCounts(1) * 0.5; % Wake
            sleepStats.SPT_minutes = sleepStats.TST_minutes + sleepStats.WASO_minutes;

            % Stage-specific minutes
            sleepStats.N1_minutes = cleanStageCounts(2) * 0.5;
            sleepStats.N2_minutes = cleanStageCounts(3) * 0.5;
            sleepStats.N3_minutes = cleanStageCounts(4) * 0.5;
            sleepStats.REM_minutes = cleanStageCounts(5) * 0.5;

            % Stage percentages (relative to TST)
            if sleepStats.TST_minutes > 0
                sleepStats.N1_percent = (sleepStats.N1_minutes / sleepStats.TST_minutes) * 100;
                sleepStats.N2_percent = (sleepStats.N2_minutes / sleepStats.TST_minutes) * 100;
                sleepStats.N3_percent = (sleepStats.N3_minutes / sleepStats.TST_minutes) * 100;
                sleepStats.REM_percent = (sleepStats.REM_minutes / sleepStats.TST_minutes) * 100;
            else
                sleepStats.N1_percent = 0;
                sleepStats.N2_percent = 0;
                sleepStats.N3_percent = 0;
                sleepStats.REM_percent = 0;
            end

            % Print summary
            fprintf('Sleep Statistics (artifact-corrected):\n');
            fprintf('  TST: %.1f min\n', sleepStats.TST_minutes);
            fprintf('  WASO: %.1f min\n', sleepStats.WASO_minutes);
            fprintf('  SPT: %.1f min\n', sleepStats.SPT_minutes);
            fprintf('  Stage distribution: N1=%.1f%%, N2=%.1f%%, N3=%.1f%%, REM=%.1f%%\n', ...
                sleepStats.N1_percent, sleepStats.N2_percent, sleepStats.N3_percent, sleepStats.REM_percent);
            fprintf('  Data quality: %.1f%% clean epochs\n', sleepStats.dataQualityPercent);
        end

        function results = performGlobalMicrostateAnalysis(obj, dataMatrix)
            % Perform global microstate analysis
            [dataProc, fsNew] = obj.preprocessData(dataMatrix, obj.fs);

            % Calculate GFP and find peaks
            gfp = obj.calculateGFP(dataProc);
            gfpPeaks = obj.findGFPPeaks(gfp, fsNew);

            fprintf('Found %d GFP peaks for global analysis\n', length(gfpPeaks));

            if length(gfpPeaks) < 10
                warning('Too few GFP peaks (<10) for reliable clustering.');
                results = [];
                return;
            end

            % Extract maps and perform clustering
            maps = dataProc(:, gfpPeaks);
            validMaps = all(isfinite(maps), 1);
            maps = maps(:, validMaps);
            gfpPeaks = gfpPeaks(validMaps);

            k = obj.microstateParams.numMaps;
            if size(maps, 2) < k
                warning('Not enough GFP peaks for %d clusters. Reducing to %d clusters.', k, size(maps, 2));
                k = max(2, size(maps, 2));
            end

            % K-means clustering
            try
                opts = statset('MaxIter', 1000, 'Display', 'off', 'UseParallel', false);
                [clusterIdx, C, sumd] = kmeans(maps', k, 'Replicates', 5, 'Options', opts, 'EmptyAction', 'singleton');
            catch ME
                warning('K-means failed: %s. Trying with fewer replicates.', ME.message);
                try
                    [clusterIdx, C, sumd] = kmeans(maps', k, 'Replicates', 2, 'Options', opts, 'EmptyAction', 'singleton');
                catch ME2
                    warning('K-means completely failed: %s', ME2.message);
                    results = [];
                    return;
                end
            end

            % Create final maps
            finalMaps = zeros(size(dataProc,1), k);
            for i = 1:k
                clusterMaps = maps(:, clusterIdx == i);
                if ~isempty(clusterMaps)
                    finalMaps(:,i) = mean(clusterMaps, 2);
                    finalMaps(:,i) = finalMaps(:,i) / norm(finalMaps(:,i));
                else
                    finalMaps(:,i) = zeros(size(dataProc,1), 1);
                end
            end

            % Segmentation
            seg = obj.performSegmentation(dataProc, finalMaps);

            % ✅ ADD ENTROPY CALCULATION HERE TOO
            entropyValue = obj.calculateMicrostateEntropy(seg, k);

            % Calculate comprehensive parameters
            [totalGEV, mapGEV] = obj.calculateGEV(dataProc, seg, finalMaps);
            [mapDuration, mapOccurrence, mapCoverage] = obj.calculateTemporalParameters(seg, k, fsNew);

            results = struct(...
                'templates', finalMaps, ...
                'segmentation', seg, ...
                'gfpPeaks', gfpPeaks, ...
                'mapGEV', mapGEV, ...
                'totalGEV', totalGEV, ...
                'numMaps', k, ...
                'fs', fsNew, ...
                'channelLabels', {obj.channelLabels}, ...
                'meanDuration', mean(mapDuration), ...
                'meanOccurrence', mean(mapOccurrence), ...
                'mapDuration', mapDuration, ...
                'mapOccurrence', mapOccurrence, ...
                'mapCoverage', mapCoverage, ...
                'entropy', entropyValue ...
                );
        end

        function [duration, occurrence, coverage] = calculateTemporalParameters(obj, segmentation, numMaps, fs)
            % Calculate comprehensive temporal parameters
            duration = zeros(1, numMaps);
            occurrence = zeros(1, numMaps);
            coverage = zeros(1, numMaps);

            totalTime = length(segmentation) / fs;

            for i = 1:numMaps
                % Find segments of this microstate
                segChanges = diff([0, segmentation == i, 0]);
                starts = find(segChanges == 1);
                ends = find(segChanges == -1) - 1;

                if isempty(starts)
                    continue;
                end

                % Duration
                segDurations = (ends - starts + 1) / fs;
                duration(i) = mean(segDurations);

                % Occurrence (per second)
                occurrence(i) = length(starts) / totalTime;

                % Coverage (percentage of total time)
                coverage(i) = sum(segDurations) / totalTime;
            end
        end

        function transitionResults = calculateTransitionProbabilities(obj, segmentation, numMaps)
            % Calculate transition probabilities between microstates
            observedTransitions = zeros(numMaps);
            validTransitions = 0;

            for t = 2:length(segmentation)
                fromState = segmentation(t-1);
                toState = segmentation(t);

                if fromState > 0 && toState > 0 && fromState ~= toState
                    observedTransitions(fromState, toState) = observedTransitions(fromState, toState) + 1;
                    validTransitions = validTransitions + 1;
                end
            end

            % Normalize to probabilities
            if validTransitions > 0
                observedTransitions = observedTransitions / validTransitions;
            end

            % Calculate expected probabilities (assuming independence)
            stateProportions = zeros(1, numMaps);
            for i = 1:numMaps
                stateProportions(i) = sum(segmentation == i) / sum(segmentation > 0);
            end

            expectedTransitions = zeros(numMaps);
            for i = 1:numMaps
                for j = 1:numMaps
                    if i ~= j
                        expectedTransitions(i, j) = stateProportions(i) * stateProportions(j);
                    end
                end
            end

            % Normalize expected probabilities
            expectedTransitions = expectedTransitions / sum(expectedTransitions(:));

            transitionResults = struct(...
                'observed', observedTransitions, ...
                'expected', expectedTransitions, ...
                'difference', observedTransitions - expectedTransitions ...
                );
        end
        function results = performMicrostateAnalysisOptimized(obj, dataProc, fsNew)
            % Optimized microstate analysis using preprocessed data

            % Calculate GFP and find peaks
            gfp = obj.calculateGFP(dataProc);
            gfpPeaks = obj.findGFPPeaks(gfp, fsNew);

            fprintf('Found %d GFP peaks for analysis\n', length(gfpPeaks));

            if length(gfpPeaks) < 10
                warning('Too few GFP peaks (<10) for reliable clustering.');
                results = [];
                return;
            end

            % Extract maps and perform clustering
            maps = dataProc(:, gfpPeaks);
            validMaps = all(isfinite(maps), 1);
            maps = maps(:, validMaps);
            gfpPeaks = gfpPeaks(validMaps);

            k = obj.microstateParams.numMaps;
            if size(maps, 2) < k
                warning('Not enough GFP peaks for %d clusters. Reducing to %d clusters.', k, size(maps, 2));
                k = max(2, size(maps, 2));
            end

            % K-means clustering
            try
                opts = statset('MaxIter', 1000, 'Display', 'off', 'UseParallel', false);
                [clusterIdx, C, sumd] = kmeans(maps', k, 'Replicates', 5, 'Options', opts, 'EmptyAction', 'singleton');
            catch ME
                warning('K-means failed: %s. Trying with fewer replicates.', ME.message);
                try
                    [clusterIdx, C, sumd] = kmeans(maps', k, 'Replicates', 2, 'Options', opts, 'EmptyAction', 'singleton');
                catch ME2
                    warning('K-means completely failed: %s', ME2.message);
                    results = [];
                    return;
                end
            end

            % Create final maps
            finalMaps = zeros(size(dataProc,1), k);
            for i = 1:k
                clusterMaps = maps(:, clusterIdx == i);
                if ~isempty(clusterMaps)
                    finalMaps(:,i) = mean(clusterMaps, 2);
                    finalMaps(:,i) = finalMaps(:,i) / norm(finalMaps(:,i));
                else
                    finalMaps(:,i) = zeros(size(dataProc,1), 1);
                end
            end

            % Segmentation
            seg = obj.performSegmentation(dataProc, finalMaps);

            % ✅ ADD THIS SECTION: Calculate metrics including entropy
            entropyValue = obj.calculateMicrostateEntropy(seg, k);

            % Calculate comprehensive parameters
            [totalGEV, mapGEV] = obj.calculateGEV(dataProc, seg, finalMaps);
            [mapDuration, mapOccurrence, mapCoverage] = obj.calculateTemporalParameters(seg, k, fsNew);

            results = struct(...
                'templates', finalMaps, ...
                'segmentation', seg, ...
                'gfpPeaks', gfpPeaks, ...
                'mapGEV', mapGEV, ...
                'totalGEV', totalGEV, ...
                'numMaps', k, ...
                'fs', fsNew, ...
                'channelLabels', {obj.channelLabels}, ...
                'meanDuration', mean(mapDuration), ...
                'meanOccurrence', mean(mapOccurrence), ...
                'mapDuration', mapDuration, ...
                'mapOccurrence', mapOccurrence, ...
                'mapCoverage', mapCoverage, ...
                'entropy', entropyValue ...  % ✅ ADD THIS
                );
        end

        function stageResults = performSleepStageAnalysisOptimized(obj, globalDataProc, fsNew, sleepStages, globalArtifactMask)
            % Optimized sleep stage analysis - Replace Wake with WASO
            stageResults = struct();

            if isempty(obj.numericHypnogram)
                fprintf('No hypnogram available for sleep stage analysis\n');
                return;
            end

            for i = 1:length(sleepStages)
                stage = sleepStages(i);

                % ✅ CHANGED: Use "WASO" instead of "Wake" for stage 0
                if stage == 0
                    stageName = 'WASO';
                    fprintf('Analyzing microstates for: %s\n', stageName);

                    % ✅ CHANGED: Create WASO mask instead of all wake
                    stageSampleMask = obj.createWASOMask(size(globalDataProc, 2));
                else
                    stageName = obj.getStageName(stage);
                    fprintf('Analyzing microstates for sleep stage: %s\n', stageName);

                    % Use regular stage mask for sleep stages
                    stageSampleMask = obj.createStageSampleMask(stage, size(globalDataProc, 2));
                end

                % Combine with artifact mask
                validStageMask = stageSampleMask & ~globalArtifactMask;

                stageData = globalDataProc(:, validStageMask);

                % Check if we have sufficient data for this stage
                stageDuration = sum(validStageMask) / fsNew;
                fprintf('  %s: %.1f seconds of clean data\n', stageName, stageDuration);

                if stageDuration > 60 % At least 1 minute of clean data
                    stageResult = obj.performMicrostateAnalysisOptimized(stageData, fsNew);
                    if ~isempty(stageResult)
                        stageResults.(stageName) = stageResult;
                        fprintf('  Successfully analyzed %s: GEV=%.3f\n', stageName, stageResult.totalGEV);
                    else
                        fprintf('  Analysis failed for %s\n', stageName);
                    end
                else
                    fprintf('  Insufficient clean data for %s analysis (%.1f s < 60 s)\n', stageName, stageDuration);
                end
            end
        end

        function entropyValue = calculateMicrostateEntropy(obj, segmentation, numMaps)
            % FAST normalized Shannon entropy only
            % Remove artifact segments (0 indicates artifacts)
            validSegments = segmentation(segmentation > 0);

            if isempty(validSegments) || length(validSegments) < 100
                entropyValue = NaN;
                return;
            end

            try
                % 1. State distribution using faster histcounts
                stateDistribution = histcounts(validSegments, 1:numMaps+1);
                totalValid = sum(stateDistribution);

                if totalValid == 0
                    entropyValue = NaN;
                    return;
                end

                stateProbabilities = stateDistribution / totalValid;

                % 2. Remove zero probabilities for entropy calculation
                nonZeroProbs = stateProbabilities(stateProbabilities > 0);

                if length(nonZeroProbs) < 2
                    entropyValue = 0; % Only one state
                    return;
                end

                % 3. Shannon entropy
                shannonEntropy = -sum(nonZeroProbs .* log2(nonZeroProbs));

                % 4. Normalized entropy (0-1 scale)
                maxEntropy = log2(numMaps);
                normalizedEntropy = shannonEntropy / maxEntropy;

                entropyValue = normalizedEntropy;

            catch ME
                fprintf('Entropy calculation error: %s\n', ME.message);
                entropyValue = NaN;
            end
        end





        function cycleResults = performSleepCycleAnalysisOptimized(obj, globalDataProc, fsNew, sleepCycles, globalArtifactMask)
            % SIMPLIFIED: Direct epoch-based cycle analysis without problematic masks
            cycleResults = struct();

            if isempty(obj.numericHypnogram) || isempty(sleepCycles)
                fprintf('No hypnogram or sleep cycles available for cycle analysis\n');
                return;
            end

            % Get unique cycles
            uniqueCycles = unique(sleepCycles(sleepCycles > 0));

            fprintf('Analyzing microstates for %d sleep cycles using direct epoch approach...\n', length(uniqueCycles));

            for cycleIdx = 1:length(uniqueCycles)
                cycleNum = uniqueCycles(cycleIdx);

                % ✅ SIMPLE APPROACH: Find start and end epochs for this cycle
                cycleEpochs = find(sleepCycles == cycleNum);

                if isempty(cycleEpochs)
                    fprintf('  Cycle %d: No epochs found\n', cycleNum);
                    continue;
                end

                startEpoch = min(cycleEpochs);
                endEpoch = max(cycleEpochs);

                fprintf('  Cycle %d: epochs %d to %d (%d epochs, %.1f min)\n', ...
                    cycleNum, startEpoch, endEpoch, length(cycleEpochs), length(cycleEpochs) * 0.5);

                % ✅ DIRECT SAMPLE EXTRACTION: Convert epochs to samples
                samplesPerEpoch = 30 * fsNew; % 30 seconds per epoch

                startSample = (startEpoch - 1) * samplesPerEpoch + 1;
                endSample = min(endEpoch * samplesPerEpoch, size(globalDataProc, 2));

                % Extract cycle data directly
                if startSample <= size(globalDataProc, 2) && endSample >= startSample
                    cycleData = globalDataProc(:, startSample:endSample);

                    % Apply artifact mask to this segment
                    cycleArtifactMask = globalArtifactMask(startSample:endSample);
                    cleanCycleData = cycleData(:, ~cycleArtifactMask);

                    % Check if we have sufficient clean data
                    cycleDuration = size(cleanCycleData, 2) / fsNew;
                    fprintf('    Clean data: %.1f seconds\n', cycleDuration);

                    if cycleDuration > 60 % At least 1 minute of clean data
                        try
                            cycleResult = obj.performMicrostateAnalysisOptimized(cleanCycleData, fsNew);
                            if ~isempty(cycleResult)
                                cycleResults.(sprintf('Cycle_%d', cycleNum)) = cycleResult;
                                fprintf('    Successfully analyzed: GEV=%.3f, %d maps\n', ...
                                    cycleResult.totalGEV, cycleResult.numMaps);
                            else
                                fprintf('    Analysis failed - insufficient GFP peaks\n');
                            end
                        catch ME
                            fprintf('    Analysis error: %s\n', ME.message);
                        end
                    else
                        fprintf('    Insufficient clean data (%.1f s < 60 s)\n', cycleDuration);
                    end
                else
                    fprintf('    Invalid sample range: %d to %d (total samples: %d)\n', ...
                        startSample, endSample, size(globalDataProc, 2));
                end
            end

            if isempty(fieldnames(cycleResults))
                fprintf('No sleep cycles successfully analyzed\n');
            else
                fprintf('Successfully analyzed %d sleep cycles\n', length(fieldnames(cycleResults)));
            end
        end




        function stageName = getStageName(obj, stageNum)
            % Convert numeric stage to name
            switch stageNum
                case 0, stageName = 'Wake';
                case 1, stageName = 'N1';
                case 2, stageName = 'N2';
                case 3, stageName = 'N3';
                case 4, stageName = 'N3'; % Combine stages 3 and 4 as N3
                case 5, stageName = 'REM';
                otherwise, stageName = sprintf('Stage_%d', stageNum);
            end
        end

        function sleepOnlyMask = createSleepOnlyMask(obj, totalSamples)
            % Create mask for SLEEP periods only (excludes wake)
            if isempty(obj.numericHypnogram)
                sleepOnlyMask = true(1, totalSamples);
                return;
            end

            % Use first channel's sampling rate for epoch calculation
            if length(obj.fs) >= 1
                fs_ref = obj.fs(1);
            else
                fs_ref = 256; % fallback
            end

            samplesPerEpoch = 30 * fs_ref;
            sleepOnlyMask = false(1, totalSamples);

            for epoch = 1:min(length(obj.numericHypnogram), ceil(totalSamples/samplesPerEpoch))
                % Include only sleep stages (N1, N2, N3, REM) - EXCLUDE WAKE (0)
                if obj.numericHypnogram(epoch) > 0
                    startSample = (epoch-1) * samplesPerEpoch + 1;
                    endSample = min(epoch * samplesPerEpoch, totalSamples);
                    sleepOnlyMask(startSample:endSample) = true;
                end
            end

            fprintf('Sleep-only mask: %d/%d samples (%.1f%%) are sleep periods\n', ...
                sum(sleepOnlyMask), totalSamples, sum(sleepOnlyMask)/totalSamples*100);
        end

        function stageSampleMask = createStageSampleMask(obj, stage, totalSamples)
            % Create sample mask for specific sleep stage with adaptive sampling rate

            if isempty(obj.numericHypnogram)
                stageSampleMask = false(1, totalSamples);
                return;
            end

            % Use first channel's sampling rate for epoch calculation
            if length(obj.fs) >= 1
                fs_ref = obj.fs(1);
            else
                fs_ref = 256; % fallback
            end

            samplesPerEpoch = 30 * fs_ref;
            stageSampleMask = false(1, totalSamples);

            for epoch = 1:min(length(obj.numericHypnogram), ceil(totalSamples/samplesPerEpoch))
                if obj.numericHypnogram(epoch) == stage
                    startSample = (epoch-1) * samplesPerEpoch + 1;
                    endSample = min(epoch * samplesPerEpoch, totalSamples);
                    stageSampleMask(startSample:endSample) = true;
                end
            end

            fprintf('  Stage %s mask: %d/%d samples (%.1f%%)\n', ...
                obj.getStageName(stage), sum(stageSampleMask), totalSamples, ...
                sum(stageSampleMask)/totalSamples*100);
        end
        function wasoMask = createWASOMask(obj, totalSamples)
            % Create mask for WASO only (wake after sleep onset)
            if isempty(obj.numericHypnogram)
                wasoMask = false(1, totalSamples);
                return;
            end

            % Use first channel's sampling rate
            if length(obj.fs) >= 1
                fs_ref = obj.fs(1);
            else
                fs_ref = 256;
            end

            samplesPerEpoch = 30 * fs_ref;
            wasoMask = false(1, totalSamples);

            % Find sleep onset (first sleep epoch)
            sleepOnsetEpoch = find(obj.numericHypnogram > 0, 1, 'first');
            if isempty(sleepOnsetEpoch)
                return; % No sleep found
            end

            % Find final sleep epoch
            sleepEpochs = find(obj.numericHypnogram > 0);
            if isempty(sleepEpochs)
                return;
            end
            finalSleepEpoch = max(sleepEpochs);

            % WASO = wake epochs between sleep onset and final sleep
            for epoch = sleepOnsetEpoch:min(finalSleepEpoch, ceil(totalSamples/samplesPerEpoch))
                if obj.numericHypnogram(epoch) == 0  % Wake stage
                    startSample = (epoch-1) * samplesPerEpoch + 1;
                    endSample = min(epoch * samplesPerEpoch, totalSamples);
                    wasoMask(startSample:endSample) = true;
                end
            end

            fprintf('  WASO mask: %d/%d samples (%.1f%%)\n', ...
                sum(wasoMask), totalSamples, sum(wasoMask)/totalSamples*100);
        end


        function printSummaryStatistics(obj)
            % Print comprehensive summary statistics
            if isempty(obj.microstateResults)
                return;
            end

            R = obj.microstateResults.sleepGlobal;

            fprintf('\n=== MICROSTATE ANALYSIS SUMMARY (TST-ONLY GLOBAL) ===\n');
            fprintf('Number of microstates: %d\n', R.numMaps);
            fprintf('Total GEV: %.3f\n', R.totalGEV);
            fprintf('Global mean duration: %.1f ms\n', R.meanDuration * 1000);
            fprintf('Global mean occurrence: %.2f Hz\n', R.meanOccurrence);
            fprintf('Normalized entropy: %.3f\n', R.entropy);
            fprintf('TST duration analyzed: %.1f hours\n', size(R.segmentation, 2)/R.fs/3600);

            % Print sleep statistics if available
            if isfield(obj.microstateResults, 'sleepStatistics')
                stats = obj.microstateResults.sleepStatistics;
                fprintf('\n=== SLEEP ARCHITECTURE ===\n');
                fprintf('TST: %.1f min, WASO: %.1f min, SPT: %.1f min\n', ...
                    stats.TST_minutes, stats.WASO_minutes, stats.SPT_minutes);
                fprintf('Stage distribution: N1=%.1f%%, N2=%.1f%%, N3=%.1f%%, REM=%.1f%%\n', ...
                    stats.N1_percent, stats.N2_percent, stats.N3_percent, stats.REM_percent);
            end

            fprintf('\nMicrostate-specific parameters:\n');
            fprintf('Map\tGEV\t\tDuration(ms)\tOccurrence(Hz)\tCoverage(%%)\n');
            for i = 1:R.numMaps
                fprintf('%d\t\t%.3f\t\t%.1f\t\t%.2f\t\t%.1f\n', ...
                    i, R.mapGEV(i), R.mapDuration(i)*1000, R.mapOccurrence(i), R.mapCoverage(i)*100);
            end

            % Print stage-specific summary if available
            if isfield(obj.microstateResults, 'stageSpecific') && ~isempty(fieldnames(obj.microstateResults.stageSpecific))
                fprintf('\n=== STAGE-SPECIFIC ENTROPY ===\n');
                stages = fieldnames(obj.microstateResults.stageSpecific);
                for i = 1:length(stages)
                    stageResult = obj.microstateResults.stageSpecific.(stages{i});
                    if ~isempty(stageResult) && isfield(stageResult, 'entropy')
                        fprintf('  %s: entropy = %.3f\n', stages{i}, stageResult.entropy);
                    end
                end
            end

            % Print cycle-specific summary if available
            if isfield(obj.microstateResults, 'cycleSpecific') && ~isempty(fieldnames(obj.microstateResults.cycleSpecific))
                fprintf('\n=== CYCLE-SPECIFIC ENTROPY ===\n');
                cycles = fieldnames(obj.microstateResults.cycleSpecific);
                for i = 1:length(cycles)
                    cycleResult = obj.microstateResults.cycleSpecific.(cycles{i});
                    if ~isempty(cycleResult) && isfield(cycleResult, 'entropy')
                        fprintf('  %s: entropy = %.3f\n', cycles{i}, cycleResult.entropy);
                    end
                end
            end
        end

        function setupMappedChannels(obj)
            fprintf('Setting up channels using ChannelMappingHelper...\n');

            % Get raw channel names - use same approach as SpindleDetectionClass
            rawChannelNames = obj.edfLoader.signal_labels;

            fprintf('Raw channel names from EDF:\n');
            for i = 1:length(rawChannelNames)
                fprintf('  Channel %d: "%s"\n', i, rawChannelNames{i});
            end

            % Map to uniform names using helper function (same as spindle detection)
            mappedNames = ChannelMappingHelper(rawChannelNames);
            obj.mappedChannelNames = rawChannelNames; % Keep original names

            % Use mapped names for channel selection
            obj.channelLabels = mappedNames;

            % Load all data - keep in cell array format (same as spindle detection)
            obj.data = obj.loadEDFData(1:length(rawChannelNames));

            % === KEY CHANGE: Get sampling rates for ALL channels ===
            obj.fs = obj.getSamplingRates();

            fprintf('All available channels: %s\n', strjoin(obj.channelLabels, ', '));
            fprintf('Sampling rates: %s Hz\n', mat2str(obj.fs));
            fprintf('Data size: %d channels\n', length(obj.data));
        end


        function data = loadEDFData(obj, channelIndices)
            % Load data using same method as SpindleDetectionClass
            fprintf('Loading data for %d channels...\n', length(channelIndices));

            try
                % Use signalCell directly - same as SpindleDetectionClass
                signalCell = obj.edfLoader.edf.signalCell;
                fprintf('Found signalCell with %d channels\n', length(signalCell));

                % Keep data in cell array format to handle different sizes
                data = cell(1, length(channelIndices));

                for i = 1:length(channelIndices)
                    channelData = signalCell{channelIndices(i)};
                    data{i} = double(channelData); % Convert to double but keep original shape
                    fprintf('  Channel %d: %s samples\n', i, mat2str(size(data{i})));
                end

                fprintf('Successfully loaded data for %d channels\n', length(data));

            catch ME
                fprintf('Error in data loading: %s\n', ME.message);
                rethrow(ME);
            end
        end

        function fs_array = getSamplingRates(obj)
            % === ADAPTIVE SAMPLING RATE HANDLING ===
            % Returns array of sampling rates for each channel
            % Handles both uniform and mixed sampling rates

            try
                sr = obj.edfLoader.sample_rate;
                if isnumeric(sr)
                    if length(sr) == 1
                        % Single sampling rate for all channels
                        fs_array = repmat(sr, 1, length(obj.channelLabels));
                        fprintf('Uniform sampling rate: %d Hz for all %d channels\n', sr, length(obj.channelLabels));
                    else
                        % Multiple sampling rates - take first N channels
                        fs_array = sr(1:length(obj.channelLabels));
                        unique_fs = unique(fs_array);
                        if length(unique_fs) > 1
                            fprintf('Mixed sampling rates detected: %s Hz\n', mat2str(unique_fs));
                            fprintf('Channel distribution:\n');
                            for i = 1:length(unique_fs)
                                count = sum(fs_array == unique_fs(i));
                                fprintf('  %d Hz: %d channels\n', unique_fs(i), count);
                            end
                        else
                            fprintf('Uniform sampling rate: %d Hz for all %d channels\n', unique_fs(1), length(obj.channelLabels));
                        end
                    end
                else
                    % Default fallback
                    fs_array = repmat(256, 1, length(obj.channelLabels));
                    fprintf('Using default sampling rate: 256 Hz for all %d channels\n', length(obj.channelLabels));
                end
            catch ME
                % Default fallback on error
                fs_array = repmat(256, 1, length(obj.channelLabels));
                fprintf('Error reading sampling rates, using default: 256 Hz for all %d channels\n', length(obj.channelLabels));
            end
        end

        function setDefaultParams(obj, p)
            % Set microstate analysis parameters
            dp = struct();
            dp.numMaps = 4;
            dp.gfpPeakDistance = 0.05; % Increased from 0.02 for fewer peaks
            dp.filterBand = [1 40];
            dp.downsampleFs = 128; % Changed to 128 for proper downsampling from 256 Hz
            dp.preferredChannels = {'F3-M2', 'F4-M1', 'C3-M2', 'C4-M1', 'O1-M2', 'O2-M1'}; % Default

            if isfield(p,'numMaps'), dp.numMaps = p.numMaps; end
            if isfield(p,'gfpPeakDistance'), dp.gfpPeakDistance = p.gfpPeakDistance; end
            if isfield(p,'filterBand'), dp.filterBand = p.filterBand; end
            if isfield(p,'downsampleFs'), dp.downsampleFs = p.downsampleFs; end
            if isfield(p,'preferredChannels'), dp.preferredChannels = p.preferredChannels; end % Auto-detected channels

            obj.microstateParams = dp;

            fprintf('Microstate parameters:\n');
            fprintf('  Number of maps: %d\n', dp.numMaps);
            fprintf('  GFP peak distance: %.3f s\n', dp.gfpPeakDistance);
            fprintf('  Filter band: %.1f-%.1f Hz\n', dp.filterBand(1), dp.filterBand(2));
            fprintf('  Downsample to: %.1f Hz\n', dp.downsampleFs);
        end

        function [dataOut, fsOut] = preprocessData(obj, data, fs)
            dp = obj.microstateParams;

            % Handle both scalar and array sampling rates
            if length(fs) > 1
                % Use the first channel's sampling rate as reference for downsampling
                fs_ref = fs(1);
                fprintf('Multiple sampling rates detected, using %.1f Hz as reference for downsampling\n', fs_ref);
            else
                fs_ref = fs;
            end

            % Convert cell array to matrix if needed
            if iscell(data)
                dataMatrix = zeros(length(data), length(data{1}));
                for i = 1:length(data)
                    dataMatrix(i, :) = data{i};
                end
                data = dataMatrix;
            end

            % Convert to double and handle NaN values properly
            data = double(data);

            % Instead of replacing all non-finite values with zeros,
            % we need to handle NaN values differently since they represent artifacts
            nanMask = any(isnan(data), 1);
            fprintf('Found %.1f%% NaN samples (artifact segments)\n', mean(nanMask)*100);

            % For preprocessing, temporarily replace NaN with zeros for filtering
            % but we'll restore NaN values after filtering
            dataTemp = data;
            dataTemp(:, nanMask) = 0;

            if any(~isfinite(dataTemp(:)))
                warning('Non-finite values found in data. Replacing with zeros.');
                dataTemp(~isfinite(dataTemp)) = 0;
            end

            % Bandpass filter - use reference sampling rate
            [b,a] = butter(2, dp.filterBand/(fs_ref/2), 'bandpass');
            dataFilt = filtfilt(b, a, dataTemp');
            dataFilt = dataFilt';

            % Restore NaN values after filtering
            dataFilt(:, nanMask) = NaN;

            % Downsample using reference sampling rate
            if fs_ref > dp.downsampleFs
                ratio = fs_ref / dp.downsampleFs;
                dataOut = resample(dataFilt', 1, round(ratio))';
                fsOut = fs_ref / round(ratio);
                fprintf('Downsampled: %.1f Hz -> %.1f Hz\n', fs_ref, fsOut);
            else
                dataOut = dataFilt;
                fsOut = fs_ref;
                fprintf('No downsampling needed: %.1f Hz\n', fs_ref);
            end

            % Remove DC offset (excluding NaN values)
            for i = 1:size(dataOut, 1)
                validData = dataOut(i, ~isnan(dataOut(i, :)));
                if ~isempty(validData)
                    dataOut(i, :) = dataOut(i, :) - mean(validData);
                end
            end

            fprintf('Preprocessing complete: %d channels, %.1f Hz, %d samples\n', ...
                size(dataOut, 1), fsOut, size(dataOut, 2));
            fprintf('Remaining NaN samples after preprocessing: %.1f%%\n', ...
                mean(any(isnan(dataOut), 1))*100);
        end


        function gfp = calculateGFP(obj, data)
            % Calculate GFP while properly handling NaN values
            gfp = zeros(1, size(data, 2));

            for t = 1:size(data, 2)
                x = data(:, t);
                validIdx = ~isnan(x);

                if sum(validIdx) >= 2  % Need at least 2 channels for meaningful GFP
                    gfp(t) = sqrt(mean(x(validIdx).^2));
                else
                    gfp(t) = NaN;  % Mark as invalid if too many NaN channels
                end
            end

            fprintf('GFP calculation: %.1f%% valid time points\n', sum(~isnan(gfp))/length(gfp)*100);
        end

        function peaks = findGFPPeaks(obj, gfp, fs)
            % Find GFP peaks for microstate analysis, excluding NaN segments
            dp = obj.microstateParams;
            minDist = max(1, round(dp.gfpPeakDistance * fs));

            % Only consider non-NaN segments for peak detection
            validGFP = gfp;
            validGFP(isnan(gfp)) = 0;  % Set NaN to 0 so they won't be detected as peaks

            [pks, locs] = findpeaks(validGFP, 'MinPeakDistance', minDist);

            % Only keep peaks that come from valid (non-NaN) GFP values
            validPeaks = ~isnan(gfp(locs));
            pks = pks(validPeaks);
            locs = locs(validPeaks);

            [~, idx] = sort(pks, 'descend');
            peaks = locs(idx);

            fprintf('Found %d GFP peaks (after excluding NaN segments)\n', length(peaks));
        end

        function seg = performSegmentation(obj, data, maps)
            % Backfitting segmentation that handles NaN values
            seg = zeros(1, size(data, 2));

            for t = 1:size(data, 2)
                x = data(:, t);

                % Skip time points with NaN values
                if any(isnan(x))
                    seg(t) = 0;  % Use 0 to indicate artifact/NaN segments
                    continue;
                end

                if norm(x) == 0 || any(~isfinite(x))
                    seg(t) = 0;
                    continue;
                end

                x = x / norm(x);
                corr = maps' * x;
                [~, seg(t)] = max(corr);
            end

            fprintf('Segmentation complete: %.1f%% valid segments\n', sum(seg > 0)/length(seg)*100);
        end

        function [totalGEV, mapGEV] = calculateGEV(obj, data, seg, maps)
            % Calculate GEV while properly handling NaN values and artifact segments
            k = size(maps, 2);
            totalGEV = 0;
            mapGEV = zeros(1, k);

            % Calculate total variance excluding NaN segments
            validData = data(:, ~any(isnan(data), 1));
            totalVariance = sum(validData.^2, 'all');

            if totalVariance == 0 || ~isfinite(totalVariance)
                warning('Invalid total variance: %f', totalVariance);
                totalGEV = 0;
                mapGEV = zeros(1, k);
                return;
            end

            validSegments = 0;
            for i = 1:k
                idx = seg == i;
                if sum(idx) > 10  % Require minimum segments for meaningful GEV
                    x = data(:, idx);

                    % Remove any segments that contain NaN values
                    validSegIdx = ~any(isnan(x), 1);
                    x = x(:, validSegIdx);

                    if size(x, 2) > 10  % Check if we still have enough segments
                        segmentVariance = sum(x.^2, 'all');
                        if segmentVariance > 0 && isfinite(segmentVariance)
                            map = maps(:, i);
                            if norm(map) > 0
                                correlation = (x' * map).^2;
                                explainedVariance = sum(correlation, 'all');
                                mapGEV(i) = explainedVariance / segmentVariance;

                                if isfinite(mapGEV(i))
                                    totalGEV = totalGEV + segmentVariance * mapGEV(i);
                                    validSegments = validSegments + 1;
                                else
                                    mapGEV(i) = 0;
                                end
                            end
                        end
                    end
                end
            end

            if validSegments > 0 && totalVariance > 0
                totalGEV = totalGEV / totalVariance;
            else
                totalGEV = 0;
            end
        end
    end
end