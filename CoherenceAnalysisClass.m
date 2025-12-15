classdef CoherenceAnalysisClass < handle
    properties
        edfPath
        xmlPath
        params
        edfLoader
        fs
        channelLabels
        data
        mappedChannelNames
        numericHypnogram
        stageMasks
        coherenceResults
        artifactDetector
        cleaningSummary
        allChannelData
        allChannelLabels
        coherenceParams
        globalArtifactMask
    end

    methods
        function obj = CoherenceAnalysisClass(edfPath, xmlPath, params)
            if nargin < 3
                params = struct();
            end
            obj.edfPath = edfPath;
            obj.xmlPath = xmlPath;
            obj.params = params;
            
            obj.coherenceParams = obj.initializeCoherenceParameters();
            
            try
                fprintf('Loading EDF file: %s\n', edfPath);
                obj.edfLoader = BlockEdfLoadClass(edfPath);
                obj.edfLoader.numCompToLoad = 3;
                obj.edfLoader.SWAP_MIN_MAX = 1;
                obj.edfLoader = obj.edfLoader.blockEdfLoad;
            catch ME
                error('Error loading EDF file with BlockEdfLoadClass: %s', ME.message);
            end
            
            obj.loadHypnogram();
            obj.setupMappedChannels();
            obj.coherenceResults = [];
            
            obj.artifactDetector = ArtifactDetectionClass();
            if isfield(params, 'ecgName')
                obj.artifactDetector.setECGParameters(params.ecgName, true);
            else
                obj.artifactDetector.setECGParameters([], true);
            end
        end

        function runAnalysis(obj, pairs)
            fprintf('Starting coherence analysis with targeted data cleaning...\n');
            
            % Extract all unique channels from pairs
            allChannels = {};
            for i = 1:length(pairs)
                channelNames = strsplit(pairs{i}, '-');
                allChannels = [allChannels, channelNames{:}];
            end
            allChannels = unique(allChannels);
            
            fprintf('Available mapped channels for matching:\n');
            for i = 1:length(obj.mappedChannelNames)
                fprintf('  %d: "%s"\n', i, obj.mappedChannelNames{i});
            end
            
            fprintf('Requested channels from pairs:\n');
            for i = 1:length(allChannels)
                fprintf('  %d: "%s"\n', i, allChannels{i});
            end
            
            % IMPROVED CHANNEL MATCHING FOR BIPOLAR MONTAGE
            eegChannelIndices = [];
            eegChannelNames = {};
            
            for ch = 1:length(allChannels)
                channelName = strtrim(allChannels{ch});
                chIdx = obj.findBipolarChannelIndex(channelName);
                
                if ~isempty(chIdx)
                    eegChannelIndices(end+1) = chIdx;
                    eegChannelNames{end+1} = obj.mappedChannelNames{chIdx};
                    fprintf('SUCCESS: Matched channel: "%s" -> "%s" (index %d)\n', channelName, obj.mappedChannelNames{chIdx}, chIdx);
                else
                    fprintf('WARNING: Could not find channel: "%s"\n', channelName);
                    fprintf('  Available channels: %s\n', strjoin(obj.mappedChannelNames, ', '));
                end
            end
            
            if isempty(eegChannelIndices)
                error('No specified channels found for analysis. Available channels: %s', strjoin(obj.mappedChannelNames, ', '));
            end
            
            fprintf('Targeted cleaning for %d EEG channels: %s\n', ...
                length(eegChannelIndices), strjoin(eegChannelNames, ', '));
            
            % Perform comprehensive artifact detection and cleaning
            [cleanData, artifactInfo] = obj.performTargetedCleaning(eegChannelIndices, eegChannelNames);
            
            % Update the main data with cleaned data
            for i = 1:length(eegChannelIndices)
                obj.data{eegChannelIndices(i)} = cleanData{i};
            end
            
            obj.cleaningSummary = obj.artifactDetector.getCleaningSummary();
            
            % Initialize results structure
            obj.coherenceResults = struct();
            obj.coherenceResults.pairs = pairs;
            obj.coherenceResults.coherence = struct();
            obj.coherenceResults.sleepStages = struct();
            obj.coherenceResults.sleepPeriods = struct();
            obj.coherenceResults.analysisParameters = obj.coherenceParams;
            
            % Perform coherence analysis for each pair
            successfulPairs = 0;
            for i = 1:length(pairs)
                pair = pairs{i};
                channelNames = strsplit(pair, '-');
                
                if length(channelNames) == 2
                    ch1 = strtrim(channelNames{1});
                    ch2 = strtrim(channelNames{2});
                    
                    % Find channel indices using bipolar matching
                    idx1 = obj.findBipolarChannelIndex(ch1);
                    idx2 = obj.findBipolarChannelIndex(ch2);
                    
                    if ~isempty(idx1) && ~isempty(idx2)
                        fprintf('Analyzing coherence pair: %s - %s\n', ch1, ch2);
                        fprintf('  Using actual channels: %s - %s\n', obj.mappedChannelNames{idx1}, obj.mappedChannelNames{idx2});
                        
if ~isempty(obj.numericHypnogram)
    obj.calculateSleepPeriodCoherence(idx1, idx2, pair);
end
                        
                        if ~isempty(obj.numericHypnogram)
                            obj.calculateStageSpecificCoherence(idx1, idx2, pair);
                             obj.calculateSleepCycleCoherence(idx1, idx2, pair);
                        end
                        
                        successfulPairs = successfulPairs + 1;
                    else
                        fprintf('WARNING: Pair %s not found in data (ch1: %s, ch2: %s)\n', pair, ch1, ch2);
                        if isempty(idx1)
                            fprintf('  Could not find channel: %s\n', ch1);
                        end
                        if isempty(idx2)
                            fprintf('  Could not find channel: %s\n', ch2);
                        end
                    end
                else
                    fprintf('WARNING: Invalid pair format: %s (should be "channel1-channel2")\n', pair);
                end
            end
            
            fprintf('Coherence analysis completed for %d/%d pairs\n', successfulPairs, length(pairs));
            if successfulPairs > 0
                obj.printSummaryStatistics();
            else
                warning('No pairs were successfully analyzed');
            end
        end

        function channelIdx = findBipolarChannelIndex(obj, channelName)
            % SPECIALIZED MATCHING FOR BIPOLAR MONTAGE
            % Handles cases where pairs are like "F3-F4" but actual channels are "F3-M2", "F4-M1"
            
            channelName = strtrim(channelName);
            
            % Common bipolar montage mappings
            bipolarMappings = {
                'F3', {'F3-M2', 'EEG F3-A2', 'F3'};
                'F4', {'F4-M1', 'EEG F4-A1', 'F4'};
                'C3', {'C3-M2', 'EEG C3-A2', 'C3'};
                'C4', {'C4-M1', 'EEG C4-A1', 'C4'};
                'O1', {'O1-M2', 'EEG O1-A2', 'O1'};
                'O2', {'O2-M1', 'EEG O2-A1', 'O2'};
                'FZ', {'FZ', 'EEG FZ'};
                'CZ', {'CZ', 'EEG CZ'};
                'PZ', {'PZ', 'EEG PZ'};
                'OZ', {'OZ', 'EEG OZ'};
                };
            
            % First try exact mapping from bipolar table
            for m = 1:size(bipolarMappings, 1)
                if strcmpi(bipolarMappings{m, 1}, channelName)
                    possibleNames = bipolarMappings{m, 2};
                    for p = 1:length(possibleNames)
                        channelIdx = find(strcmpi(obj.mappedChannelNames, possibleNames{p}), 1);
                        if ~isempty(channelIdx)
                            return;
                        end
                    end
                end
            end
            
            % Strategy 1: Exact match (case-insensitive)
            channelIdx = find(strcmpi(obj.mappedChannelNames, channelName), 1);
            if ~isempty(channelIdx), return; end
            
            % Strategy 2: Channel starts with the requested name
            for j = 1:length(obj.mappedChannelNames)
                if startsWith(obj.mappedChannelNames{j}, channelName)
                    channelIdx = j;
                    return;
                end
            end
            
            % Strategy 3: Channel contains the requested name
            for j = 1:length(obj.mappedChannelNames)
                if contains(obj.mappedChannelNames{j}, channelName)
                    channelIdx = j;
                    return;
                end
            end
            
            % Strategy 4: Common variations with references
            variations = {
                channelName, ...
                [channelName '-M2'], ...
                [channelName '-M1'], ...
                [channelName '-A2'], ...
                [channelName '-A1'], ...
                ['EEG ' channelName '-A2'], ...
                ['EEG ' channelName '-A1'], ...
                ['EEG ' channelName]
                };
            
            for v = 1:length(variations)
                channelIdx = find(strcmpi(obj.mappedChannelNames, variations{v}), 1);
                if ~isempty(channelIdx)
                    return;
                end
            end
            
            % Final fallback: return empty
            channelIdx = [];
        end

        function saveResults(obj, outputFile)
    if isempty(obj.coherenceResults)
        error('No results to save. Run analysis first.');
    end
    
    fprintf('Saving coherence results to: %s\n', outputFile);
    
    if exist(outputFile, 'file')
        delete(outputFile);
    end
    
    % Get comprehensive table
    resultsTable = obj.createComprehensiveResultsTable();
    
    % Save different analysis types in separate sheets
    if height(resultsTable) > 0
        % Global results
        globalMask = strcmp(resultsTable.AnalysisType, 'Global');
        if any(globalMask)
            writetable(resultsTable(globalMask, :), outputFile, 'Sheet', 'Global_Coherence');
        end
        
        % Sleep period results
        periodMask = strcmp(resultsTable.AnalysisType, 'SleepPeriod');
        if any(periodMask)
            writetable(resultsTable(periodMask, :), outputFile, 'Sheet', 'Sleep_Periods');
        end
        
        % Sleep stage results
        stageMask = strcmp(resultsTable.AnalysisType, 'SleepStage');
        if any(stageMask)
            writetable(resultsTable(stageMask, :), outputFile, 'Sheet', 'Sleep_Stages');
        end

        % In saveResults method, after other writetable calls, add:
cycleMask = strcmp(resultsTable.AnalysisType, 'SleepCycle');
if any(cycleMask)
    writetable(resultsTable(cycleMask, :), outputFile, 'Sheet', 'Sleep_Cycles');
end
        
        % All results combined
        writetable(resultsTable, outputFile, 'Sheet', 'All_Results');
    end
    
    % Calculate and save network composites
    networkData = obj.calculateNetworkComposites();
    if ~isempty(networkData)
        writetable(networkData, outputFile, 'Sheet', 'Network_Composites');
    end
    
    % Save data quality and parameters (your existing code)
    if ~isempty(obj.cleaningSummary)
        qualityData = {
            'Total_Recording_Time_min', length(obj.allChannelData{1}) / obj.fs(1) / 60;
            'Clean_Data_Percent', obj.cleaningSummary.cleanDataPercentage;
            'Artifact_Percent', obj.cleaningSummary.artifactPercentage;
            'ECG_Decontamination_Applied', obj.cleaningSummary.ecgDecontaminationApplied;
            'Total_Artifacts', obj.cleaningSummary.totalArtifacts;
            };
        qualityTable = cell2table(qualityData, 'VariableNames', {'Parameter', 'Value'});
        writetable(qualityTable, outputFile, 'Sheet', 'Data_Quality');
    end
    
    paramData = {
        'Window_Length_sec', obj.coherenceParams.windowLength;
        'Window_Overlap_Percent', obj.coherenceParams.overlap * 100;
        'Minimum_Data_Length_sec', obj.coherenceParams.minDataLength;
        'Frequency_Range_Min_Hz', obj.coherenceParams.freqRange(1);
        'Frequency_Range_Max_Hz', obj.coherenceParams.freqRange(2);
        'NFFT_Size', obj.coherenceParams.nfft;
        };
    paramTable = cell2table(paramData, 'VariableNames', {'Parameter', 'Value'});
    writetable(paramTable, outputFile, 'Sheet', 'Analysis_Parameters');
    
    fprintf('SUCCESS: Saved comprehensive coherence results to: %s\n', outputFile);
end
        
function printSummaryStatistics(obj)
    if isempty(obj.coherenceResults)
        return;
    end
    
    fprintf('\n=== COHERENCE ANALYSIS SUMMARY ===\n');
    fprintf('Pairs analyzed: %s\n', strjoin(obj.coherenceResults.pairs, ', '));
    
    if ~isempty(obj.cleaningSummary)
        fprintf('Data quality: %.1f%% clean data\n', obj.cleaningSummary.cleanDataPercentage);
        fprintf('Artifact contamination: %.1f%%\n', obj.cleaningSummary.artifactPercentage);
    end
    
    if ~isempty(obj.coherenceResults.pairs)
        firstPair = obj.coherenceResults.pairs{1};
        sanitizedPair = obj.sanitizeFieldName(firstPair);
        
        % REPLACED: Use SPT instead of Global coherence
        if isfield(obj.coherenceResults.sleepPeriods, sanitizedPair) && ...
           isfield(obj.coherenceResults.sleepPeriods.(sanitizedPair), 'SPT')
            coherenceData = obj.coherenceResults.sleepPeriods.(sanitizedPair).SPT;
            
            fprintf('\n=== COHERENCE METRICS FOR %s (SPT) ===\n', firstPair);
            fprintf('SPT Mean Coherence: %.3f\n', coherenceData.meanCoherence);
            fprintf('Peak Coherence: %.3f at %.1f Hz\n', ...
                coherenceData.peakCoherence, coherenceData.peakFrequency);
            
            fprintf('Band Coherence:\n');
            fprintf('  Delta (0.5-4 Hz): %.3f\n', coherenceData.bandCoherence.Delta);
            fprintf('  Theta (4-8 Hz): %.3f\n', coherenceData.bandCoherence.Theta);
            fprintf('  Alpha (8-12 Hz): %.3f\n', coherenceData.bandCoherence.Alpha);
            fprintf('  Sigma (12-15 Hz): %.3f\n', coherenceData.bandCoherence.Sigma);
            fprintf('  Beta (15-30 Hz): %.3f\n', coherenceData.bandCoherence.Beta);
            fprintf('  Gamma (30-45 Hz): %.3f\n', coherenceData.bandCoherence.Gamma);
        else
            fprintf('\nNo SPT coherence data available for summary\n');
        end
    end
end



        function network_data = calculateNetworkComposites(obj)
    % Calculate network-level composite coherence measures
    % Returns a table with network composites for each analysis type
    
    if isempty(obj.coherenceResults)
        network_data = [];
        return;
    end
    
    fprintf('Calculating network composites...\n');
    
    % Define network configurations
    networks = {
        'InterHemispheric', {'F3-F4', 'C3-C4', 'O1-O2'};
        'AnteriorPosterior', {'F3-C3', 'F4-C4'};
        'CentralOccipital', {'C3-O1', 'C4-O2'};
        'Frontal', {'F3-F4'};
        'Central', {'C3-C4'};
        'Occipital', {'O1-O2'};
        };
    
    % Get all available analysis types and stages
    analysisTypes = {'SleepPeriod', 'SleepStage'};
    allStages = {};
    
    % Collect all unique stages
    for i = 1:length(obj.coherenceResults.pairs)
        pair = obj.coherenceResults.pairs{i};
        sanitizedPair = obj.sanitizeFieldName(pair);
        
        % Check sleep periods
        if isfield(obj.coherenceResults.sleepPeriods, sanitizedPair)
            periods = fieldnames(obj.coherenceResults.sleepPeriods.(sanitizedPair));
            allStages = union(allStages, periods);
        end
        
        % Check sleep stages
        if isfield(obj.coherenceResults.sleepStages, sanitizedPair)
            stages = fieldnames(obj.coherenceResults.sleepStages.(sanitizedPair));
            allStages = union(allStages, stages);
        end
    end

    % ADD THIS: Explicitly add NREM if not already found
    if ~ismember('NREM', allStages)
        allStages = union(allStages, {'NREM'});
    end
    
    allStages = union({'Global'}, allStages);
    
    % Initialize results table
    networkRows = {};
    
    for netIdx = 1:size(networks, 1)
        networkName = networks{netIdx, 1};
        requiredPairs = networks{netIdx, 2};
        
        fprintf('  Calculating %s network from pairs: %s\n', ...
            networkName, strjoin(requiredPairs, ', '));
        
        for stageIdx = 1:length(allStages)
            stage = allStages{stageIdx};
            
            % Determine analysis type
            if strcmp(stage, 'Global')
                analysisType = 'Global';
            elseif ismember(stage, {'SPT', 'TST', 'WASO'})
                analysisType = 'SleepPeriod';
            else
                analysisType = 'SleepStage';
            end
            
            % Collect coherence values for all pairs in this network
            coherenceValues = [];
            bandCoherence = struct();
            hasValidData = false;
            
            for pairIdx = 1:length(requiredPairs)
                pair = requiredPairs{pairIdx};
                sanitizedPair = obj.sanitizeFieldName(pair);
                
                % Get coherence data for this pair and stage
                cohData = obj.getCoherenceDataForStage(sanitizedPair, analysisType, stage);
                
                if ~isempty(cohData)
                    coherenceValues(end+1) = cohData.meanCoherence;
                    hasValidData = true;
                    
                    % Accumulate band coherence
                    if isfield(cohData, 'bandCoherence')
                        bands = fieldnames(cohData.bandCoherence);
                        for b = 1:length(bands)
                            band = bands{b};
                            if ~isfield(bandCoherence, band)
                                bandCoherence.(band) = [];
                            end
                            bandCoherence.(band)(end+1) = cohData.bandCoherence.(band);
                        end
                    end
                end
            end
            
            if hasValidData && ~isempty(coherenceValues)
                % Calculate network composite
                networkRow = struct();
                networkRow.Network = networkName;
                networkRow.AnalysisType = analysisType;
                networkRow.SleepStage = stage;
                networkRow.MeanCoherence = mean(coherenceValues);
                networkRow.StdCoherence = std(coherenceValues);
                networkRow.NumPairs = length(coherenceValues);
                networkRow.PairsUsed = strjoin(requiredPairs, '; ');
                
                % Calculate mean band coherence
                bands = fieldnames(bandCoherence);
                for b = 1:length(bands)
                    band = bands{b};
                    if ~isempty(bandCoherence.(band))
                        networkRow.(['Coherence_' band]) = mean(bandCoherence.(band));
                    else
                        networkRow.(['Coherence_' band]) = NaN;
                    end
                end
                
                networkRows{end+1} = networkRow;
                fprintf('    %s - %s: mean coherence = %.3f (%d pairs)\n', ...
                    networkName, stage, networkRow.MeanCoherence, networkRow.NumPairs);
            end
        end
    end
    
    % Convert to table
    if ~isempty(networkRows)
        network_data = struct2table([networkRows{:}]);
    else
        network_data = table();
        fprintf('    No network composites could be calculated\n');
    end
end

function cohData = getCoherenceDataForStage(obj, sanitizedPair, analysisType, stage)
    % Helper function to get coherence data for specific analysis type and stage
    cohData = [];
    
    switch analysisType
        case 'Global'
            if isfield(obj.coherenceResults.coherence, sanitizedPair)
                cohData = obj.coherenceResults.coherence.(sanitizedPair);
            end
            
        case 'SleepPeriod'
            if isfield(obj.coherenceResults.sleepPeriods, sanitizedPair) && ...
               isfield(obj.coherenceResults.sleepPeriods.(sanitizedPair), stage)
                cohData = obj.coherenceResults.sleepPeriods.(sanitizedPair).(stage);
            end
            
        case 'SleepStage'
            if isfield(obj.coherenceResults.sleepStages, sanitizedPair) && ...
               isfield(obj.coherenceResults.sleepStages.(sanitizedPair), stage)
                cohData = obj.coherenceResults.sleepStages.(sanitizedPair).(stage);
            end
    end
end
    end

    methods (Access = private)
        function loadHypnogram(obj)
            try
                if isempty(obj.xmlPath) || ~exist(obj.xmlPath, 'file')
                    fprintf('No XML file provided for hypnogram.\n');
                    obj.numericHypnogram = [];
                    return;
                end

                fprintf('Loading hypnogram: %s\n', obj.xmlPath);

                lcaObj = loadCompumedicsAnnotationsClass(obj.xmlPath);
                lcaObj.scoreKey = { ...
                    {'Awake', 0, 'W'}; {'1', 1, '1'}; {'2', 2, '2'}; ...
                    {'3', 3, '3'}; {'4', 4, '4'}; {'REM', 5, 'R'}; ...
                    {'X', 9, 'X'}; {'X', 10, 'X'}};
                lcaObj.GET_SCORED_EVENTS = 0;
                lcaObj = lcaObj.loadFile;

                obj.numericHypnogram = lcaObj.numericHypnogram;

                obj.stageMasks = struct();
                obj.stageMasks.W = obj.numericHypnogram == 0;
                obj.stageMasks.N1 = obj.numericHypnogram == 1;
                obj.stageMasks.N2 = obj.numericHypnogram == 2;
                obj.stageMasks.N3 = obj.numericHypnogram == 3 | obj.numericHypnogram == 4;
                obj.stageMasks.REM = obj.numericHypnogram == 5;

                fprintf('Hypnogram loaded: %d epochs\n', length(obj.numericHypnogram));

            catch ME
                warning('Hypnogram loading failed: %s', ME.message);
                obj.numericHypnogram = [];
                obj.stageMasks = [];
            end
        end
        
        function setupMappedChannels(obj)
            fprintf('Setting up channels using ChannelMappingHelper...\n');

            rawChannelNames = obj.edfLoader.signal_labels;

            fprintf('Raw channel names from EDF:\n');
            for i = 1:length(rawChannelNames)
                fprintf('  Channel %d: "%s"\n', i, rawChannelNames{i});
            end

            obj.mappedChannelNames = ChannelMappingHelper(rawChannelNames);
            obj.channelLabels = obj.mappedChannelNames;
            obj.data = obj.loadEDFData(1:length(rawChannelNames));
            obj.fs = obj.getSamplingRates();

            fprintf('All available channels (MAPPED): %s\n', strjoin(obj.channelLabels, ', '));
            fprintf('Sampling rates: %s Hz\n', mat2str(obj.fs));
            fprintf('Data size: %d channels\n', length(obj.data));
            
            obj.allChannelData = obj.data;
            obj.allChannelLabels = obj.mappedChannelNames;
        end
        
        function data = loadEDFData(obj, channelIndices)
            fprintf('Loading data for %d channels...\n', length(channelIndices));

            try
                signalCell = obj.edfLoader.edf.signalCell;
                fprintf('Found signalCell with %d channels\n', length(signalCell));

                data = cell(1, length(channelIndices));

                for i = 1:length(channelIndices)
                    channelData = signalCell{channelIndices(i)};
                    data{i} = double(channelData);
                    fprintf('  Channel %d: %s samples\n', i, mat2str(size(data{i})));
                end

                fprintf('Successfully loaded data for %d channels\n', length(data));

            catch ME
                fprintf('Error in data loading: %s\n', ME.message);
                rethrow(ME);
            end
        end
        
        function fs_array = getSamplingRates(obj)
            try
                sr = obj.edfLoader.sample_rate;
                if isnumeric(sr)
                    if length(sr) == 1
                        fs_array = repmat(sr, 1, length(obj.channelLabels));
                        fprintf('Uniform sampling rate: %d Hz for all %d channels\n', sr, length(obj.channelLabels));
                    else
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
                    fs_array = repmat(256, 1, length(obj.channelLabels));
                    fprintf('Using default sampling rate: 256 Hz for all %d channels\n', length(obj.channelLabels));
                end
            catch ME
                fs_array = repmat(256, 1, length(obj.channelLabels));
                fprintf('Error reading sampling rates, using default: 256 Hz\n');
            end
        end
        
        function params = initializeCoherenceParameters(obj)
            params = struct();
            params.windowLength = 4;
            params.overlap = 0.5;
            params.freqRange = [0.5, 45];
            params.minDataLength = 30;
            
            params.frequencyBands = {
                'Delta',    [0.5, 4.0];
                'Theta',    [4.0, 8.0];
                'Alpha',    [8.0, 12.0];
                'Sigma',    [12.0, 15.0];
                'Beta',     [15.0, 30.0];
                'Gamma',    [30.0, 45.0];
                };
            
            params.coherenceThreshold = 0.5;
            params.confidenceLevel = 0.95;
            params.nfft = 1024;
        end
        
        function [cleanData, artifactInfo] = performTargetedCleaning(obj, eegChannelIndices, eegChannelNames)
            cleaningChannels = eegChannelIndices;
            cleaningLabels = eegChannelNames;

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

            cleaning_fs = obj.fs(1);

            [cleanData, artifactInfo] = obj.artifactDetector.fullDataCleaning(...
                dataToClean, labelsToClean, cleaning_fs, obj.numericHypnogram);

            if isfield(artifactInfo, 'globalArtifactMask')
                obj.globalArtifactMask = artifactInfo.globalArtifactMask;
            else
                fprintf('Warning: globalArtifactMask not found, creating default mask\n');
                obj.globalArtifactMask = false(1, length(dataToClean{1}));
            end

            cleanData = cleanData(1:length(eegChannelIndices));
        end
        
        function calculateSleepPeriodCoherence(obj, idx1, idx2, pairName)
            if isempty(obj.numericHypnogram)
                return;
            end
            
            data1 = obj.data{idx1};
            data2 = obj.data{idx2};
            fs = obj.fs(1);
            
            fprintf('  Calculating sleep period coherence for %s\n', pairName);
            
            tstMask = obj.createTSTMask(length(data1));
            sptMask = obj.createSPTMask(length(data1));
            wasoMask = obj.createWASOMask(length(data1));
            
            sanitizedPair = obj.sanitizeFieldName(pairName);
            
            if ~isfield(obj.coherenceResults, 'sleepPeriods')
                obj.coherenceResults.sleepPeriods = struct();
            end
            obj.coherenceResults.sleepPeriods.(sanitizedPair) = struct();
            
            if sum(tstMask) > 30 * fs
                tstData1 = data1(tstMask);
                tstData2 = data2(tstMask);
                tstCoherence = obj.calculateCoherenceForData(tstData1, tstData2, fs);
                tstCoherence.periodName = 'TST';
                tstCoherence.dataLength = length(tstData1) / fs;
                obj.coherenceResults.sleepPeriods.(sanitizedPair).TST = tstCoherence;
                fprintf('    TST coherence: mean=%.3f, duration=%.1f min\n', ...
                    tstCoherence.meanCoherence, tstCoherence.dataLength/60);
            end
            
            if sum(sptMask) > 30 * fs
                sptData1 = data1(sptMask);
                sptData2 = data2(sptMask);
                sptCoherence = obj.calculateCoherenceForData(sptData1, sptData2, fs);
                sptCoherence.periodName = 'SPT';
                sptCoherence.dataLength = length(sptData1) / fs;
                obj.coherenceResults.sleepPeriods.(sanitizedPair).SPT = sptCoherence;
                fprintf('    SPT coherence: mean=%.3f, duration=%.1f min\n', ...
                    sptCoherence.meanCoherence, sptCoherence.dataLength/60);
            end
            
            if sum(wasoMask) > 30 * fs
                wasoData1 = data1(wasoMask);
                wasoData2 = data2(wasoMask);
                wasoCoherence = obj.calculateCoherenceForData(wasoData1, wasoData2, fs);
                wasoCoherence.periodName = 'WASO';
                wasoCoherence.dataLength = length(wasoData1) / fs;
                obj.coherenceResults.sleepPeriods.(sanitizedPair).WASO = wasoCoherence;
                fprintf('    WASO coherence: mean=%.3f, duration=%.1f min\n', ...
                    wasoCoherence.meanCoherence, wasoCoherence.dataLength/60);
            end
            

        end
        
        function sptMask = createSPTMask(obj, totalSamples)
            if isempty(obj.numericHypnogram)
                sptMask = false(1, totalSamples);
                return;
            end

            fs_ref = obj.fs(1);
            samplesPerEpoch = 30 * fs_ref;
            sptMask = false(1, totalSamples);

            sleepEpochs = find(obj.numericHypnogram >= 1 & obj.numericHypnogram <= 5);
            
            if isempty(sleepEpochs)
                fprintf('  No sleep epochs found for SPT calculation\n');
                return;
            end
            
            sptStart = min(sleepEpochs);
            sptEnd = max(sleepEpochs);
            
            for epoch = sptStart:sptEnd
                if epoch <= length(obj.numericHypnogram)
                    startSample = (epoch-1) * samplesPerEpoch + 1;
                    endSample = min(epoch * samplesPerEpoch, totalSamples);
                    sptMask(startSample:endSample) = true;
                end
            end

            fprintf('  SPT mask: %d/%d samples (%.1f%%) are within sleep period\n', ...
                sum(sptMask), totalSamples, sum(sptMask)/totalSamples*100);
        end

        function tstMask = createTSTMask(obj, totalSamples)
            if isempty(obj.numericHypnogram)
                tstMask = false(1, totalSamples);
                return;
            end

            fs_ref = obj.fs(1);
            samplesPerEpoch = 30 * fs_ref;
            tstMask = false(1, totalSamples);

            for epoch = 1:min(length(obj.numericHypnogram), ceil(totalSamples/samplesPerEpoch))
                if obj.numericHypnogram(epoch) >= 1 && obj.numericHypnogram(epoch) <= 5
                    startSample = (epoch-1) * samplesPerEpoch + 1;
                    endSample = min(epoch * samplesPerEpoch, totalSamples);
                    tstMask(startSample:endSample) = true;
                end
            end

            fprintf('  TST mask: %d/%d samples (%.1f%%) are sleep periods\n', ...
                sum(tstMask), totalSamples, sum(tstMask)/totalSamples*100);
        end

        function wasoMask = createWASOMask(obj, totalSamples)
            if isempty(obj.numericHypnogram)
                wasoMask = false(1, totalSamples);
                return;
            end

            fs_ref = obj.fs(1);
            samplesPerEpoch = 30 * fs_ref;
            wasoMask = false(1, totalSamples);

            sleepEpochs = find(obj.numericHypnogram >= 1 & obj.numericHypnogram <= 5);
            
            if isempty(sleepEpochs)
                fprintf('  No sleep epochs found for WASO calculation\n');
                return;
            end
            
            sptStart = min(sleepEpochs);
            sptEnd = max(sleepEpochs);
            
            for epoch = sptStart:sptEnd
                if epoch <= length(obj.numericHypnogram) && obj.numericHypnogram(epoch) == 0
                    startSample = (epoch-1) * samplesPerEpoch + 1;
                    endSample = min(epoch * samplesPerEpoch, totalSamples);
                    wasoMask(startSample:endSample) = true;
                end
            end

            fprintf('  WASO mask: %d/%d samples (%.1f%%) are wake after sleep onset\n', ...
                sum(wasoMask), totalSamples, sum(wasoMask)/totalSamples*100);
        end
        
        function result = calculateComprehensiveCoherence(obj, idx1, idx2)
            data1 = obj.data{idx1};
            data2 = obj.data{idx2};
            fs = obj.fs(1);
            
            fprintf('  Calculating comprehensive coherence: %s vs %s (fs=%.1f Hz)\n', ...
                obj.mappedChannelNames{idx1}, obj.mappedChannelNames{idx2}, fs);
            
            minLength = min(length(data1), length(data2));
            data1 = data1(1:minLength)';
            data2 = data2(1:minLength)';
            
            if any(isnan(data1)) || any(isnan(data2))
                fprintf('    Removing NaN values...\n');
                validMask = ~isnan(data1) & ~isnan(data2);
                data1 = data1(validMask);
                data2 = data2(validMask);
            end
            
            if length(data1) < obj.coherenceParams.minDataLength * fs
                warning('Insufficient data length for reliable coherence analysis');
                result = obj.createEmptyCoherenceResult();
                return;
            end
            
            windowLength = obj.coherenceParams.windowLength * fs;
            overlap = obj.coherenceParams.overlap;
            nfft = obj.coherenceParams.nfft;
            
            [cxy, f] = mscohere(data1, data2, hamming(windowLength), ...
                round(overlap * windowLength), nfft, fs);
            
            freqMask = f >= obj.coherenceParams.freqRange(1) & f <= obj.coherenceParams.freqRange(2);
            f = f(freqMask);
            cxy = cxy(freqMask);
            
            result = struct();
            result.frequencies = f;
            result.coherence = cxy;
            result.meanCoherence = mean(cxy);
            result.medianCoherence = median(cxy);
            result.stdCoherence = std(cxy);
            result.coherenceVariance = var(cxy);
            [result.peakCoherence, peakIdx] = max(cxy);
            result.peakFrequency = f(peakIdx);
            result.coherenceBandwidth = obj.calculateBandwidth(cxy, f);
            result.coherenceArea = trapz(f, cxy);
            result.dominantFrequency = sum(f .* cxy) / sum(cxy);
            result.spectralEntropy = obj.calculateSpectralEntropy(cxy);
            result.bandCoherence = obj.calculateBandCoherence(cxy, f);
            result.coherenceRatios = obj.calculateCoherenceRatios(result.bandCoherence);
            result.dataLength = length(data1) / fs;
            result.validWindows = length(cxy);
            result.samplingRate = fs;
            
            fprintf('    Comprehensive metrics calculated:\n');
            fprintf('      Mean=%.3f, Peak=%.3f@%.1fHz, Bandwidth=%.2fHz\n', ...
                result.meanCoherence, result.peakCoherence, result.peakFrequency, result.coherenceBandwidth);
        end
        
        function bandwidth = calculateBandwidth(~, coherence, frequencies)
            maxCoherence = max(coherence);
            halfMax = maxCoherence / 2;
            
            aboveThreshold = coherence >= halfMax;
            if any(aboveThreshold)
                bandwidth = max(frequencies(aboveThreshold)) - min(frequencies(aboveThreshold));
            else
                bandwidth = 0;
            end
        end
        
        function entropy = calculateSpectralEntropy(~, coherence)
            normalizedCoherence = coherence / sum(coherence);
            entropy = -sum(normalizedCoherence .* log2(normalizedCoherence + eps));
        end
        
        function bandCoherence = calculateBandCoherence(obj, coherence, frequencies)
            bandCoherence = struct();
            
            for i = 1:size(obj.coherenceParams.frequencyBands, 1)
                bandName = obj.coherenceParams.frequencyBands{i, 1};
                bandRange = obj.coherenceParams.frequencyBands{i, 2};
                
                bandMask = frequencies >= bandRange(1) & frequencies <= bandRange(2);
                if any(bandMask)
                    bandCoherence.(bandName) = mean(coherence(bandMask));
                else
                    bandCoherence.(bandName) = 0;
                end
            end
        end
        
        function ratios = calculateCoherenceRatios(~, bandCoherence)
            ratios = struct();
            
            if isfield(bandCoherence, 'Delta') && isfield(bandCoherence, 'Theta')
                ratios.DeltaTheta = bandCoherence.Delta / (bandCoherence.Theta + eps);
            end
            
            if isfield(bandCoherence, 'Alpha') && isfield(bandCoherence, 'Beta')
                ratios.AlphaBeta = bandCoherence.Alpha / (bandCoherence.Beta + eps);
            end
            
            if isfield(bandCoherence, 'Sigma') && isfield(bandCoherence, 'Delta')
                ratios.SigmaDelta = bandCoherence.Sigma / (bandCoherence.Delta + eps);
            end
            
            if isfield(bandCoherence, 'Gamma') && isfield(bandCoherence, 'Beta')
                ratios.GammaBeta = bandCoherence.Gamma / (bandCoherence.Beta + eps);
            end
        end
        
        function result = createEmptyCoherenceResult(obj)
            result = struct();
            result.frequencies = [];
            result.coherence = [];
            result.meanCoherence = NaN;
            result.medianCoherence = NaN;
            result.stdCoherence = NaN;
            result.coherenceVariance = NaN;
            result.peakCoherence = NaN;
            result.peakFrequency = NaN;
            result.coherenceBandwidth = NaN;
            result.coherenceArea = NaN;
            result.dominantFrequency = NaN;
            result.spectralEntropy = NaN;
            result.dataLength = NaN;
            result.validWindows = NaN;
            result.samplingRate = obj.fs(1);
            
            for i = 1:size(obj.coherenceParams.frequencyBands, 1)
                bandName = obj.coherenceParams.frequencyBands{i, 1};
                result.bandCoherence.(bandName) = NaN;
            end
            
            result.coherenceRatios = struct();
        end
        
        function calculateStageSpecificCoherence(obj, idx1, idx2, pairName)
    if isempty(obj.numericHypnogram) || isempty(obj.stageMasks)
        fprintf('  No hypnogram available for stage-specific coherence\n');
        return;
    end
    
    data1 = obj.data{idx1};
    data2 = obj.data{idx2};
    fs = obj.fs(1);
    
    samplesPerEpoch = 30 * fs;
    numCompleteEpochs = min(floor(length(data1) / samplesPerEpoch), length(obj.numericHypnogram));
    
    % ADD NREM TO THE LIST
    stages = {'N1', 'N2', 'N3', 'REM', 'WASO', 'NREM'};
    sanitizedPair = obj.sanitizeFieldName(pairName);
    obj.coherenceResults.sleepStages.(sanitizedPair) = struct();
    
    fprintf('  Stage-specific coherence analysis (%d epochs):\n', numCompleteEpochs);
    
    for s = 1:length(stages)
        stage = stages{s};
        
        if strcmp(stage, 'WASO')
            % === EXISTING WASO CODE ===
            stageMask = obj.createWASOMask(length(data1));
            stageEpochs = sum(stageMask) / samplesPerEpoch;
            
        elseif strcmp(stage, 'NREM')
            % === NEW NREM CODE ===
            fprintf('    Calculating NREM (N2+N3 combined):\n');
            
            % Get masks for N2 and N3
            n2Mask = obj.stageMasks.N2;
            n3Mask = obj.stageMasks.N3;
            
            % Combine N2 and N3 epochs
            nremMask = n2Mask | n3Mask;
            stageEpochs = sum(nremMask(1:numCompleteEpochs));
            
        else
            % === EXISTING CODE FOR N1, N2, N3, REM ===
            stageMask = obj.stageMasks.(stage);
            stageEpochs = sum(stageMask(1:numCompleteEpochs));
        end
        
        if stageEpochs > 0
            fprintf('    %s: %.1f epochs', stage, stageEpochs);
            
            % For NREM, add N2/N3 breakdown
            if strcmp(stage, 'NREM')
                fprintf(' (N2: %.0f, N3: %.0f)', ...
                    sum(n2Mask(1:numCompleteEpochs)), ...
                    sum(n3Mask(1:numCompleteEpochs)));
            end
            fprintf('\n');
            
            stageData1 = [];
            stageData2 = [];
            
            if strcmp(stage, 'WASO')
                % === EXISTING WASO DATA EXTRACTION ===
                stageData1 = data1(stageMask);
                stageData2 = data2(stageMask);
                
            elseif strcmp(stage, 'NREM')
                % === NEW NREM DATA EXTRACTION ===
                for epoch = 1:numCompleteEpochs
                    if nremMask(epoch)
                        startSample = (epoch-1) * samplesPerEpoch + 1;
                        endSample = min(epoch * samplesPerEpoch, length(data1));
                        
                        epochData1 = data1(startSample:endSample);
                        epochData2 = data2(startSample:endSample);
                        
                        if sum(isnan(epochData1)) / length(epochData1) < 0.5 && ...
                           sum(isnan(epochData2)) / length(epochData2) < 0.5
                            stageData1 = [stageData1; epochData1];
                            stageData2 = [stageData2; epochData2];
                        end
                    end
                end
                
            else
                % === EXISTING DATA EXTRACTION FOR N1, N2, N3, REM ===
                for epoch = 1:numCompleteEpochs
                    if stageMask(epoch)
                        startSample = (epoch-1) * samplesPerEpoch + 1;
                        endSample = min(epoch * samplesPerEpoch, length(data1));
                        
                        epochData1 = data1(startSample:endSample);
                        epochData2 = data2(startSample:endSample);
                        
                        if sum(isnan(epochData1)) / length(epochData1) < 0.5 && ...
                           sum(isnan(epochData2)) / length(epochData2) < 0.5
                            stageData1 = [stageData1; epochData1];
                            stageData2 = [stageData2; epochData2];
                        end
                    end
                end
            end
            
            if length(stageData1) > 30 * fs
                stageCoherence = obj.calculateCoherenceForData(stageData1, stageData2, fs);
                stageCoherence.stageEpochs = stageEpochs;
                
                % Add N2/N3 info for NREM
                if strcmp(stage, 'NREM')
                    stageCoherence.N2_epochs = sum(n2Mask(1:numCompleteEpochs));
                    stageCoherence.N3_epochs = sum(n3Mask(1:numCompleteEpochs));
                end
                
                obj.coherenceResults.sleepStages.(sanitizedPair).(stage) = stageCoherence;
                
                fprintf('      Coherence: mean=%.3f', stageCoherence.meanCoherence);
                
                % Only show peak frequency for non-NREM stages (optional)
                if ~strcmp(stage, 'NREM')
                    fprintf(', peak=%.3f@%.1fHz', ...
                        stageCoherence.peakCoherence, stageCoherence.peakFrequency);
                end
                fprintf('\n');
                
            else
                fprintf('      Insufficient clean data (%.1f s < 30 s)\n', length(stageData1)/fs);
            end
        end
    end
end


        function calculateSleepCycleCoherence(obj, idx1, idx2, pairName)
    if isempty(obj.numericHypnogram)
        return;
    end
    
    try
        % Use your existing sleep_cycles function
        cycles_vector = sleep_cycles(obj.numericHypnogram);
        
        % Extract cycle start and end epochs from the vector
        unique_cycles = unique(cycles_vector);
        unique_cycles = unique_cycles(unique_cycles > 0); % Remove zeros
        
        if isempty(unique_cycles)
            fprintf('  No sleep cycles detected\n');
            return;
        end
        
        data1 = obj.data{idx1};
        data2 = obj.data{idx2};
        fs = obj.fs(1);
        
        sanitizedPair = obj.sanitizeFieldName(pairName);
        
        % Initialize sleep cycles structure
        if ~isfield(obj.coherenceResults, 'sleepCycles')
            obj.coherenceResults.sleepCycles = struct();
        end
        obj.coherenceResults.sleepCycles.(sanitizedPair) = struct();
        
        fprintf('  Sleep cycle coherence (%d cycles):\n', length(unique_cycles));
        
        for cycleIdx = 1:length(unique_cycles)
            cycle_num = unique_cycles(cycleIdx);
            
            % Find start and end epochs for this cycle
            cycle_epochs = find(cycles_vector == cycle_num);
            if isempty(cycle_epochs)
                continue;
            end
            
            startEpoch = min(cycle_epochs);
            endEpoch = max(cycle_epochs);
            
            cycleMask = false(1, length(data1));
            
            % Create mask for this cycle using start/end epochs
            samplesPerEpoch = 30 * fs;
            for epoch = startEpoch:endEpoch
                if epoch <= length(obj.numericHypnogram)
                    startSample = (epoch-1) * samplesPerEpoch + 1;
                    endSample = min(epoch * samplesPerEpoch, length(data1));
                    cycleMask(startSample:endSample) = true;
                end
            end
            
            if sum(cycleMask) > 30 * fs  % At least 30 seconds of data
                cycleData1 = data1(cycleMask);
                cycleData2 = data2(cycleMask);
                
                cycleCoherence = obj.calculateCoherenceForData(cycleData1, cycleData2, fs);
                cycleCoherence.cycleNumber = cycle_num;
                cycleCoherence.startEpoch = startEpoch;
                cycleCoherence.endEpoch = endEpoch;
                cycleCoherence.durationMinutes = length(cycleData1) / fs / 60;
                
                cycleField = sprintf('Cycle%d', cycle_num);
                obj.coherenceResults.sleepCycles.(sanitizedPair).(cycleField) = cycleCoherence;
                
                fprintf('    Cycle %d: %.3f coherence, %.1f min, epochs %d-%d\n', ...
                    cycle_num, cycleCoherence.meanCoherence, ...
                    cycleCoherence.durationMinutes, startEpoch, endEpoch);
            end
        end
    catch ME
        fprintf('  Error in sleep cycle coherence: %s\n', ME.message);
    end
end

        function result = calculateCoherenceForData(obj, data1, data2, fs)
    minLength = min(length(data1), length(data2));
    data1 = data1(1:minLength)';
    data2 = data2(1:minLength)';
    
    validMask = ~isnan(data1) & ~isnan(data2);
    data1 = data1(validMask);
    data2 = data2(validMask);
    
    windowLength = obj.coherenceParams.windowLength * fs;
    overlap = obj.coherenceParams.overlap;
    nfft = obj.coherenceParams.nfft;
    
    [cxy, f] = mscohere(data1, data2, hamming(windowLength), ...
        round(overlap * windowLength), nfft, fs);
    
    freqMask = f >= obj.coherenceParams.freqRange(1) & f <= obj.coherenceParams.freqRange(2);
    f = f(freqMask);
    cxy = cxy(freqMask);
    
    result = struct();
    result.frequencies = f;
    result.coherence = cxy;
    result.meanCoherence = mean(cxy);
    result.medianCoherence = median(cxy);
    result.stdCoherence = std(cxy);
    result.coherenceVariance = var(cxy);
    [result.peakCoherence, peakIdx] = max(cxy);
    result.peakFrequency = f(peakIdx);
    result.coherenceBandwidth = obj.calculateBandwidth(cxy, f);
    result.coherenceArea = trapz(f, cxy);
    result.dominantFrequency = sum(f .* cxy) / sum(cxy);
    result.spectralEntropy = obj.calculateSpectralEntropy(cxy);
    
    % FIX: Ensure band coherence is always calculated
    result.bandCoherence = obj.calculateBandCoherence(cxy, f);
    result.coherenceRatios = obj.calculateCoherenceRatios(result.bandCoherence);
    
    result.dataLength = length(data1) / fs;
    result.validWindows = length(cxy);
end
        
function resultsTable = createComprehensiveResultsTable(obj)
    pairs = obj.coherenceResults.pairs;
    
    % Initialize table structure
    columnNames = {
        'Pair', 'AnalysisType', 'SleepStage', 'MeanCoherence', ...
        'MedianCoherence', 'PeakCoherence', 'PeakFrequency_Hz', ...
        'CoherenceBandwidth_Hz', 'CoherenceArea', 'CoherenceVariance', ...
        'DominantFrequency_Hz', 'SpectralEntropy', ...
        'Coherence_Delta', 'Coherence_Theta', 'Coherence_Alpha', ...
        'Coherence_Sigma', 'Coherence_Beta', 'Coherence_Gamma', ...
        'Ratio_DeltaTheta', 'Ratio_AlphaBeta', 'Ratio_SigmaDelta', 'Ratio_GammaBeta', ...
        'DataLength_sec', 'ValidWindows', 'StageEpochs'
        };
    
    % Initialize empty table
    resultsTable = cell2table(cell(0, length(columnNames)), 'VariableNames', columnNames);
    
    for i = 1:length(pairs)
        pair = pairs{i};
        sanitizedPair = obj.sanitizeFieldName(pair);
        

        
        % SLEEP PERIOD RESULTS
        if isfield(obj.coherenceResults.sleepPeriods, sanitizedPair)
            periodResults = obj.coherenceResults.sleepPeriods.(sanitizedPair);
            periods = fieldnames(periodResults);
            
            for p = 1:length(periods)
                period = periods{p};
                periodCoherence = periodResults.(period);
                periodRow = obj.createTableRow(pair, 'SleepPeriod', period, periodCoherence);
                resultsTable = [resultsTable; periodRow];
            end
        end
        
        % STAGE-SPECIFIC RESULTS
        if isfield(obj.coherenceResults.sleepStages, sanitizedPair)
            stageResults = obj.coherenceResults.sleepStages.(sanitizedPair);
            stages = fieldnames(stageResults);
            
            for s = 1:length(stages)
                stage = stages{s};
                stageCoherence = stageResults.(stage);
                stageRow = obj.createTableRow(pair, 'SleepStage', stage, stageCoherence);
                resultsTable = [resultsTable; stageRow];
            end
        end

        % SLEEP CYCLE RESULTS
if isfield(obj.coherenceResults, 'sleepCycles') && ...
   isfield(obj.coherenceResults.sleepCycles, sanitizedPair)
    cycleResults = obj.coherenceResults.sleepCycles.(sanitizedPair);
    cycles = fieldnames(cycleResults);
    
    for c = 1:length(cycles)
        cycle = cycles{c};
        cycleCoherence = cycleResults.(cycle);
        cycleRow = obj.createTableRow(pair, 'SleepCycle', cycle, cycleCoherence);
        resultsTable = [resultsTable; cycleRow];
    end
end

    end
end

function row = createTableRow(obj, pair, analysisType, stage, coherenceData)
    % Create a single table row from coherence data
    row = table();
    row.Pair = {pair};
    row.AnalysisType = {analysisType};
    row.SleepStage = {stage};
    row.MeanCoherence = coherenceData.meanCoherence;
    row.MedianCoherence = coherenceData.medianCoherence;
    row.PeakCoherence = coherenceData.peakCoherence;
    row.PeakFrequency_Hz = coherenceData.peakFrequency;
    row.CoherenceBandwidth_Hz = coherenceData.coherenceBandwidth;
    row.CoherenceArea = coherenceData.coherenceArea;
    row.CoherenceVariance = coherenceData.coherenceVariance;
    row.DominantFrequency_Hz = coherenceData.dominantFrequency;
    row.SpectralEntropy = coherenceData.spectralEntropy;
    
    % Band coherence (with NaN protection)
    bands = {'Delta', 'Theta', 'Alpha', 'Sigma', 'Beta', 'Gamma'};
    for b = 1:length(bands)
        bandName = bands{b};
        if isfield(coherenceData, 'bandCoherence') && isfield(coherenceData.bandCoherence, bandName)
            row.(['Coherence_' bandName]) = coherenceData.bandCoherence.(bandName);
        else
            row.(['Coherence_' bandName]) = NaN;
        end
    end
    
    % Coherence ratios (with NaN protection)
    ratios = {'DeltaTheta', 'AlphaBeta', 'SigmaDelta', 'GammaBeta'};
    for r = 1:length(ratios)
        ratioName = ratios{r};
        if isfield(coherenceData, 'coherenceRatios') && isfield(coherenceData.coherenceRatios, ratioName)
            row.(['Ratio_' ratioName]) = coherenceData.coherenceRatios.(ratioName);
        else
            row.(['Ratio_' ratioName]) = NaN;
        end
    end
    
    % Data quality metrics
    row.DataLength_sec = coherenceData.dataLength;
    row.ValidWindows = coherenceData.validWindows;
    
    if isfield(coherenceData, 'stageEpochs')
        row.StageEpochs = coherenceData.stageEpochs;
    else
        row.StageEpochs = NaN;
    end
end
        
        function safeName = sanitizeFieldName(~, originalName)
            safeName = regexprep(originalName, '[^a-zA-Z0-9_]', '_');
            
            if ~isempty(safeName) && ~isletter(safeName(1))
                safeName = ['Channel_', safeName];
            end
            
            if isempty(safeName)
                safeName = 'UnknownChannel';
            end
        end
    end
end