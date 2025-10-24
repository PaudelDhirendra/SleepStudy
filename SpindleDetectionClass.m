classdef SpindleDetectionClass < handle
    % SpindleDetectionClass: Detect sleep spindles using Mölle et al. (2011) method
    % Implements topography-based separation of slow (frontal) and fast (centro-parietal) spindles
    % WITH ADAPTIVE SAMPLING RATE HANDLING

    properties
        edfLoader
        fs                    % Array of sampling rates for each channel
        channelLabels
        data
        spindleEvents      % [start_s, end_s, peak_s, RMS_amplitude, duration_s, frequency_Hz, channel_idx]
        detectionParams
        edfPath
        xmlPath
        mappedChannelNames
        numericHypnogram
        stage2Mask
        stage3Mask
        artifactDetector
        cleaningSummary

        % Mölle method specific properties
        SO_events          % Slow oscillation events [peak_time, duration, amplitude, channel_idx]
        slow_spindles      % Slow spindle events (frontal)
        fast_spindles      % Fast spindle events (centro-parietal)
        temporalRelations  % SO-spindle timing relationships
    end

    methods
        function obj = SpindleDetectionClass(edfFile, xmlFile, params)
            if nargin < 3
                params = struct();
            end
            obj.edfPath = edfFile;
            obj.xmlPath = xmlFile;

            try
                fprintf('Loading EDF file: %s\n', edfFile);
                obj.edfLoader = BlockEdfLoadClass(edfFile);
                obj.edfLoader.numCompToLoad = 3;
                obj.edfLoader.SWAP_MIN_MAX = 1;
                obj.edfLoader = obj.edfLoader.blockEdfLoad;
            catch ME
                error('Error loading EDF file with BlockEdfLoadClass: %s', ME.message);
            end

            obj.loadHypnogram();
            obj.setupMappedChannels();
            obj.setDefaultParams(params);
            obj.spindleEvents = [];

            obj.artifactDetector = ArtifactDetectionClass();

            % Set ECG parameters from params if provided
            if nargin >= 3 && isfield(params, 'ecgName')
                obj.artifactDetector.setECGParameters(params.ecgName, params.denoiseEcg);
            end

            % Initialize Mölle method properties
            obj.SO_events = [];
            obj.slow_spindles = [];
            obj.fast_spindles = [];
            obj.temporalRelations = struct();
        end

        function runDetection(obj, channels, references, just2)
            % Main detection method using Mölle et al. (2011) approach
            fprintf('Starting spindle detection using Mölle et al. (2011) method...\n');

            % Data cleaning
            eegChannelIndices = [];
            eegChannelNames = {};

            for ch = 1:length(channels)
                channelName = channels{ch};
                chIdx = find(strcmp(obj.channelLabels, channelName));
                if ~isempty(chIdx)
                    eegChannelIndices(end+1) = chIdx;
                    eegChannelNames{end+1} = channelName;
                end
            end

            if isempty(eegChannelIndices)
                warning('No specified channels found for cleaning');
                return;
            end

            fprintf('Targeted cleaning for %d EEG channels: %s\n', ...
                length(eegChannelIndices), strjoin(eegChannelNames, ', '));

            cleaningChannels = eegChannelIndices;
            cleaningLabels = eegChannelNames;

            if obj.artifactDetector.denoiseEcg
                ecgIdx = obj.artifactDetector.findECGChannel(obj.channelLabels);
                if ~isempty(ecgIdx)
                    cleaningChannels(end+1) = ecgIdx;
                    cleaningLabels{end+1} = obj.channelLabels{ecgIdx};
                    fprintf('Including ECG channel for decontamination: %s\n', obj.channelLabels{ecgIdx});
                end
            end

            dataToClean = cell(1, length(cleaningChannels));
            labelsToClean = cell(1, length(cleaningChannels));
            for i = 1:length(cleaningChannels)
                dataToClean{i} = obj.data{cleaningChannels(i)};
                labelsToClean{i} = cleaningLabels{i};
            end

            % Use first channel's sampling rate for cleaning (assuming consistent within subject)
            cleaning_fs = obj.fs(1);
            [cleanData, artifactInfo] = obj.artifactDetector.fullDataCleaning(...
                dataToClean, labelsToClean, cleaning_fs, obj.numericHypnogram);

            for i = 1:length(eegChannelIndices)
                obj.data{eegChannelIndices(i)} = cleanData{i};
            end

            obj.cleaningSummary = obj.artifactDetector.getCleaningSummary();

            % Set default parameters - Mölle method only detects in NREM sleep
            if nargin < 4
                just2 = true; % Default to NREM sleep only (N2 + SWS)
            end
            if nargin < 3
                references = {};
            end

            % Run Mölle detection method
            fprintf('Running Mölle et al. (2011) spindle detection...\n');

            try
                % 1. Detect Slow Oscillations (in NREM sleep only)
                fprintf('Detecting slow oscillations in NREM sleep...\n');
                obj.SO_events = obj.detectSlowOscillations();

                % 2. Detect Spindles with topography separation (NREM sleep only)
                fprintf('Detecting slow and fast spindles in NREM sleep...\n');
                [obj.slow_spindles, obj.fast_spindles] = obj.detectSpindlesMolleMethod(just2);

                % 3. Combine all spindles
                obj.spindleEvents = [obj.slow_spindles; obj.fast_spindles];

                % 4. Analyze temporal relationships
                if ~isempty(obj.SO_events) && (~isempty(obj.slow_spindles) || ~isempty(obj.fast_spindles))
                    fprintf('Analyzing temporal relationships...\n');
                    obj.analyzeTemporalRelationships();
                end

                fprintf('Mölle detection completed:\n');
                fprintf('  Slow oscillations: %d\n', size(obj.SO_events, 1));
                fprintf('  Slow spindles: %d\n', size(obj.slow_spindles, 1));
                fprintf('  Fast spindles: %d\n', size(obj.fast_spindles, 1));
                fprintf('  Total spindles: %d\n', size(obj.spindleEvents, 1));

            catch ME
                fprintf('Error in spindle detection: %s\n', ME.message);
                % Initialize empty results to prevent further errors
                obj.SO_events = [];
                obj.slow_spindles = [];
                obj.fast_spindles = [];
                obj.spindleEvents = [];
                rethrow(ME);
            end
        end

        function saveResults(obj, outputFile)
            % Save comprehensive results using Mölle method
            if isempty(obj.spindleEvents)
                warning('No spindles to save.');

                % Create empty tables with proper structure
                emptySpindleTable = table();
                emptyGlobalTable = table();
                emptyChannelTable = table();
                emptySOTable = table();
                emptyStageTable = table();
                emptyCycleTable = table();
                emptyQualityTable = table();

                writetable(emptySpindleTable, outputFile, 'Sheet', 'Individual_Spindles');
                writetable(emptyGlobalTable, outputFile, 'Sheet', 'Global_Statistics');
                writetable(emptyChannelTable, outputFile, 'Sheet', 'Channel_Statistics');
                writetable(emptySOTable, outputFile, 'Sheet', 'Slow_Oscillations');
                writetable(emptyStageTable, outputFile, 'Sheet', 'Stage_Statistics');
                writetable(emptyCycleTable, outputFile, 'Sheet', 'Cycle_Statistics');
                writetable(emptyQualityTable, outputFile, 'Sheet', 'Data_Quality');

                fprintf('Saved empty results to: %s\n', outputFile);
                return;
            end

            fprintf('Saving comprehensive Mölle et al. (2011) method results...\n');

            %% 1. INDIVIDUAL SPINDLE EVENTS
            fprintf('Building individual spindle table...\n');

            nSpindles = size(obj.spindleEvents, 1);
            channelNames = cell(nSpindles, 1);
            stageLabels = cell(nSpindles, 1);
            cycleNumbers = zeros(nSpindles, 1);
            spindleTypes = cell(nSpindles, 1);
            topographicalRegions = cell(nSpindles, 1);

            % Create base table
            T = array2table(obj.spindleEvents, ...
                'VariableNames', {'Start_sec','End_sec','Peak_sec','RMS_Amplitude','Duration_sec','Frequency_Hz','ChannelIdx'});

            % Classify spindle types based on topography and frequency
            frontalChannels = {'F3-M2', 'F4-M1', 'F3', 'F4', 'Fz', 'F1', 'F2'};
            centralChannels = {'C3-M2', 'C4-M1', 'C3', 'C4', 'Cz', 'C1', 'C2', 'P3', 'P4', 'Pz'};

            for i = 1:nSpindles
                if T.ChannelIdx(i) <= length(obj.channelLabels)
                    channelNames{i} = obj.channelLabels{T.ChannelIdx(i)};

                    % Classify based on topography (Mölle method)
                    if any(strcmp(frontalChannels, channelNames{i}))
                        topographicalRegions{i} = 'Frontal';
                        spindleTypes{i} = 'Slow';
                    elseif any(strcmp(centralChannels, channelNames{i}))
                        topographicalRegions{i} = 'Central';
                        spindleTypes{i} = 'Fast';
                    else
                        topographicalRegions{i} = 'Other';
                        % Classify by frequency if topography unknown
                        if T.Frequency_Hz(i) >= 11 && T.Frequency_Hz(i) < 13.5
                            spindleTypes{i} = 'Slow';
                        elseif T.Frequency_Hz(i) >= 13.5 && T.Frequency_Hz(i) <= 16
                            spindleTypes{i} = 'Fast';
                        else
                            spindleTypes{i} = 'Atypical';
                        end
                    end
                else
                    channelNames{i} = 'Unknown';
                    topographicalRegions{i} = 'Unknown';
                    spindleTypes{i} = 'Unknown';
                end
            end

            T.ChannelName = channelNames;
            T.TopographicalRegion = topographicalRegions;
            T.SpindleType = spindleTypes;

            % Add sleep stage information
            if ~isempty(obj.numericHypnogram)
                fprintf('Adding sleep stage information...\n');

                for i = 1:nSpindles
                    epochNumber = ceil(T.Peak_sec(i) / 30);
                    if epochNumber <= length(obj.numericHypnogram)
                        stageNum = obj.numericHypnogram(epochNumber);
                        switch stageNum
                            case 0, stageLabels{i} = 'W';
                            case 1, stageLabels{i} = 'N1';
                            case 2, stageLabels{i} = 'N2';
                            case 3, stageLabels{i} = 'N3';
                            case 4, stageLabels{i} = 'N3';
                            case 5, stageLabels{i} = 'REM';
                            otherwise, stageLabels{i} = 'Unknown';
                        end
                    else
                        stageLabels{i} = 'Unknown';
                    end
                end
                T.SleepStage = stageLabels;
            else
                T.SleepStage = repmat({'Unknown'}, nSpindles, 1);
            end

            %% 2. SLOW OSCILLATION EVENTS
            SO_table = table();
            SO_cycleNumbers = [];
            if ~isempty(obj.SO_events)
                SO_table = array2table(obj.SO_events, ...
                    'VariableNames', {'Peak_sec','Duration_sec','Amplitude_uV','ChannelIdx'});

                SO_channelNames = cell(size(SO_table, 1), 1);
                for i = 1:size(SO_table, 1)
                    if SO_table.ChannelIdx(i) <= length(obj.channelLabels)
                        SO_channelNames{i} = obj.channelLabels{SO_table.ChannelIdx(i)};
                    else
                        SO_channelNames{i} = 'Unknown';
                    end
                end
                SO_table.ChannelName = SO_channelNames;

                % Add sleep stage information for SOs
                if ~isempty(obj.numericHypnogram)
                    SO_stageLabels = cell(size(SO_table, 1), 1);
                    for i = 1:size(SO_table, 1)
                        epochNumber = ceil(SO_table.Peak_sec(i) / 30);
                        if epochNumber <= length(obj.numericHypnogram)
                            stageNum = obj.numericHypnogram(epochNumber);
                            switch stageNum
                                case 0, SO_stageLabels{i} = 'W';
                                case 1, SO_stageLabels{i} = 'N1';
                                case 2, SO_stageLabels{i} = 'N2';
                                case 3, SO_stageLabels{i} = 'N3';
                                case 4, SO_stageLabels{i} = 'N3';
                                case 5, SO_stageLabels{i} = 'REM';
                                otherwise, SO_stageLabels{i} = 'Unknown';
                            end
                        else
                            SO_stageLabels{i} = 'Unknown';
                        end
                    end
                    SO_table.SleepStage = SO_stageLabels;
                end
            end

            %% 3. COMPREHENSIVE SUMMARY STATISTICS
            fprintf('Building summary statistics...\n');
            totalSleepTime = obj.calculateTotalSleepTime();
            totalNREMTime = obj.calculateNREMTime(); % N2 + SWS time for Mölle method

            % Calculate separate N2 and N3 times
            if ~isempty(obj.numericHypnogram)
                N2_time = sum(obj.numericHypnogram == 2) * 30 / 60;
                N3_time = sum(obj.numericHypnogram == 3 | obj.numericHypnogram == 4) * 30 / 60;
            else
                N2_time = 0;
                N3_time = 0;
            end

            % Calculate sleep cycles from NREM sleep only
            cycleStats = table();
            cycleNumbers = zeros(nSpindles, 1);
            nCycles = 0;
            meanCycleDuration = 0;
            stdCycleDuration = 0;
            totalCycleSpindles = 0;
            meanSpindlesPerCycle = 0;

            if ~isempty(obj.numericHypnogram)
                fprintf('Adding cycle information (NREM-based)...\n');
                try
                    cycles = [];
                    if exist('sleep_cycles', 'file')
                        try
                            % Create NREM-only hypnogram for cycle detection
                            nrem_hypnogram = obj.numericHypnogram;
                            % Set wake and REM to 0, keep NREM stages as is
                            nrem_hypnogram(nrem_hypnogram == 0 | nrem_hypnogram == 1 | nrem_hypnogram == 5) = 0;

                            cycles = sleep_cycles(nrem_hypnogram);
                            nCycles = length(unique(cycles(cycles > 0)));
                            fprintf('Identified %d sleep cycles from NREM sleep\n', nCycles);

                            % Assign cycles to spindles
                            for i = 1:nSpindles
                                epochNumber = ceil(T.Peak_sec(i) / 30);
                                if epochNumber <= length(cycles)
                                    cycleNumbers(i) = cycles(epochNumber);
                                end
                            end
                            T.CycleNumber = cycleNumbers;

                            % Assign cycles to SOs
                            if ~isempty(obj.SO_events)
                                SO_cycleNumbers = zeros(size(obj.SO_events, 1), 1);
                                for i = 1:size(obj.SO_events, 1)
                                    epochNumber = ceil(obj.SO_events(i,1) / 30);
                                    if epochNumber <= length(cycles)
                                        SO_cycleNumbers(i) = cycles(epochNumber);
                                    end
                                end
                            end

                            % Create cycle statistics table
                            uniqueCycles = unique(cycles(cycles > 0));
                            nCycles = length(uniqueCycles);

                            cycleStats = table('Size', [nCycles, 8], ...
                                'VariableTypes', {'cell', 'double', 'double', 'double', 'double', 'double', 'double', 'double'}, ...
                                'VariableNames', {'Cycle', 'Total_Spindle_Count', 'Slow_Spindle_Count', 'Fast_Spindle_Count', ...
                                'SO_Count', 'Spindle_Density_per_min', 'Slow_Spindle_Density_per_min', 'Fast_Spindle_Density_per_min'});

                            totalCycleTime = zeros(nCycles, 1);

                            for i = 1:nCycles
                                cycleNum = uniqueCycles(i);

                                % Count spindles in this cycle
                                cycleSpindles = sum(cycleNumbers == cycleNum);
                                cycleSlow = sum(cycleNumbers == cycleNum & strcmp(spindleTypes, 'Slow'));
                                cycleFast = sum(cycleNumbers == cycleNum & strcmp(spindleTypes, 'Fast'));

                                % Count SOs in this cycle
                                if ~isempty(SO_cycleNumbers)
                                    cycleSOs = sum(SO_cycleNumbers == cycleNum);
                                else
                                    cycleSOs = 0;
                                end

                                % Calculate cycle duration (NREM epochs in this cycle)
                                cycleEpochs = sum(cycles == cycleNum);
                                cycleDuration = cycleEpochs * 30 / 60; % minutes
                                totalCycleTime(i) = cycleDuration;

                                cycleStats.Cycle{i} = sprintf('Cycle_%d', cycleNum);
                                cycleStats.Total_Spindle_Count(i) = cycleSpindles;
                                cycleStats.Slow_Spindle_Count(i) = cycleSlow;
                                cycleStats.Fast_Spindle_Count(i) = cycleFast;
                                cycleStats.SO_Count(i) = cycleSOs;
                                cycleStats.Spindle_Density_per_min(i) = cycleSpindles / max(cycleDuration, 0.1);
                                cycleStats.Slow_Spindle_Density_per_min(i) = cycleSlow / max(cycleDuration, 0.1);
                                cycleStats.Fast_Spindle_Density_per_min(i) = cycleFast / max(cycleDuration, 0.1);
                            end

                            % Add cycle summary to global stats
                            if nCycles > 0
                                meanCycleDuration = mean(totalCycleTime);
                                stdCycleDuration = std(totalCycleTime);
                                totalCycleSpindles = sum(cycleStats.Total_Spindle_Count);
                                meanSpindlesPerCycle = mean(cycleStats.Total_Spindle_Count);
                            end

                        catch ME
                            fprintf('Cycle detection failed: %s\n', ME.message);
                            cycles = [];
                            T.CycleNumber = zeros(nSpindles, 1);
                        end
                    else
                        fprintf('sleep_cycles function not available\n');
                        T.CycleNumber = zeros(nSpindles, 1);
                    end

                catch ME
                    fprintf('Error in cycle assignment: %s\n', ME.message);
                    T.CycleNumber = zeros(nSpindles, 1);
                end
            else
                T.CycleNumber = zeros(nSpindles, 1);
            end

            % Spindle statistics - TOTAL
            slowSpindles = sum(strcmp(spindleTypes, 'Slow'));
            fastSpindles = sum(strcmp(spindleTypes, 'Fast'));
            atypicalSpindles = sum(strcmp(spindleTypes, 'Atypical'));
            totalSpindles = nSpindles;

            % Spindle statistics - BY STAGE
            N2_spindles = obj.countSpindlesInStage(2);
            N3_spindles = obj.countSpindlesInStage(3) + obj.countSpindlesInStage(4);
            N2_slow = obj.countSpindlesInStageByType(2, 'Slow');
            N2_fast = obj.countSpindlesInStageByType(2, 'Fast');
            N3_slow = obj.countSpindlesInStageByType(3, 'Slow') + obj.countSpindlesInStageByType(4, 'Slow');
            N3_fast = obj.countSpindlesInStageByType(3, 'Fast') + obj.countSpindlesInStageByType(4, 'Fast');

            % Density calculations
            spindleDensity_NREM = totalSpindles / totalNREMTime;
            spindleDensity_N2 = N2_spindles / max(N2_time, 0.1);
            spindleDensity_N3 = N3_spindles / max(N3_time, 0.1);
            slowSpindleDensity_N2 = N2_slow / max(N2_time, 0.1);
            fastSpindleDensity_N2 = N2_fast / max(N2_time, 0.1);
            slowSpindleDensity_N3 = N3_slow / max(N3_time, 0.1);
            fastSpindleDensity_N3 = N3_fast / max(N3_time, 0.1);

            % SO statistics
            if ~isempty(obj.SO_events)
                SO_count = size(obj.SO_events, 1);
                SO_N2 = obj.countSOsInStage(2);
                SO_N3 = obj.countSOsInStage(3) + obj.countSOsInStage(4);
                SO_density_NREM = SO_count / totalNREMTime;
                SO_density_N2 = SO_N2 / max(N2_time, 0.1);
                SO_density_N3 = SO_N3 / max(N3_time, 0.1);

                % Calculate SO characteristics
                SO_duration_mean = mean(obj.SO_events(:,2)) * 1000;
                SO_duration_std = std(obj.SO_events(:,2)) * 1000;
                SO_amplitude_mean = mean(abs(obj.SO_events(:,3)));
                SO_amplitude_std = std(abs(obj.SO_events(:,3)));
            else
                SO_count = 0; SO_N2 = 0; SO_N3 = 0;
                SO_density_NREM = 0; SO_density_N2 = 0; SO_density_N3 = 0;
                SO_duration_mean = 0; SO_duration_std = 0;
                SO_amplitude_mean = 0; SO_amplitude_std = 0;
            end

            % Topographical statistics
            frontalSpindles = sum(strcmp(topographicalRegions, 'Frontal'));
            centralSpindles = sum(strcmp(topographicalRegions, 'Central'));
            otherSpindles = sum(strcmp(topographicalRegions, 'Other'));

            % Global Statistics Table
            globalStats = {
                % Total counts
                'Total_Spindle_Count', totalSpindles;
                'Slow_Spindle_Count', slowSpindles;
                'Fast_Spindle_Count', fastSpindles;
                'Atypical_Spindle_Count', atypicalSpindles;
                'Slow_Oscillation_Count', SO_count;

                % Sleep stage durations
                'Total_Sleep_Time_min', totalSleepTime;
                'NREM_Sleep_Time_min', totalNREMTime;
                'N2_Sleep_Time_min', N2_time;
                'N3_Sleep_Time_min', N3_time;

                % Cycle statistics
                'Number_of_Sleep_Cycles', nCycles;
                'Mean_Cycle_Duration_min', meanCycleDuration;
                'Std_Cycle_Duration_min', stdCycleDuration;
                'Total_Spindles_in_Cycles', totalCycleSpindles;
                'Mean_Spindles_per_Cycle', meanSpindlesPerCycle;

                % Spindle densities - NREM combined
                'Spindle_Density_per_min_NREM', spindleDensity_NREM;
                'Slow_Spindle_Density_per_min_NREM', slowSpindles / totalNREMTime;
                'Fast_Spindle_Density_per_min_NREM', fastSpindles / totalNREMTime;

                % Spindle densities - SEPARATE N2/N3
                'Spindle_Density_per_min_N2', spindleDensity_N2;
                'Spindle_Density_per_min_N3', spindleDensity_N3;
                'Slow_Spindle_Density_per_min_N2', slowSpindleDensity_N2;
                'Fast_Spindle_Density_per_min_N2', fastSpindleDensity_N2;
                'Slow_Spindle_Density_per_min_N3', slowSpindleDensity_N3;
                'Fast_Spindle_Density_per_min_N3', fastSpindleDensity_N3;

                % SO densities - SEPARATE N2/N3
                'SO_Density_per_min_NREM', SO_density_NREM;
                'SO_Density_per_min_N2', SO_density_N2;
                'SO_Density_per_min_N3', SO_density_N3;

                % Ratios and other stats
                'Slow_Fast_Ratio', slowSpindles / max(fastSpindles, 1);
                'N2_N3_Spindle_Ratio', N2_spindles / max(N3_spindles, 1);
                'SO_Spindle_Ratio_NREM', SO_count / max(totalSpindles, 1);

                % Individual spindle characteristics
                'Mean_Spindle_Duration_ms', mean(T.Duration_sec) * 1000;
                'Std_Spindle_Duration_ms', std(T.Duration_sec) * 1000;
                'Mean_Spindle_Frequency_Hz', mean(T.Frequency_Hz);
                'Std_Spindle_Frequency_Hz', std(T.Frequency_Hz);
                'Mean_Slow_Spindle_Frequency_Hz', mean(T.Frequency_Hz(strcmp(spindleTypes, 'Slow')));
                'Mean_Fast_Spindle_Frequency_Hz', mean(T.Frequency_Hz(strcmp(spindleTypes, 'Fast')));

                % SO characteristics
                'Mean_SO_Duration_ms', SO_duration_mean;
                'Std_SO_Duration_ms', SO_duration_std;
                'Mean_SO_Amplitude_uV', SO_amplitude_mean;
                'Std_SO_Amplitude_uV', SO_amplitude_std;

                % Topographical statistics
                'Frontal_Spindle_Count', frontalSpindles;
                'Central_Spindle_Count', centralSpindles;
                'Other_Spindle_Count', otherSpindles;
                'Frontal_Spindle_Percentage', (frontalSpindles / totalSpindles) * 100;
                'Central_Spindle_Percentage', (centralSpindles / totalSpindles) * 100;

                % Data quality
                'Artifact_Free_Sleep_Percent', obj.cleaningSummary.cleanDataPercentage;
                'ECG_Decontamination_Applied', obj.cleaningSummary.ecgDecontaminationApplied;
                };

            globalTable = cell2table(globalStats, 'VariableNames', {'Parameter', 'Value'});

            % Channel-specific Statistics
            channels = unique(obj.spindleEvents(:,7));
            nChannels = length(channels);

            channelStats = table('Size', [nChannels, 8], ...
                'VariableTypes', {'cell', 'double', 'double', 'double', 'double', 'double', 'double', 'cell'}, ...
                'VariableNames', {'Channel', 'Total_Spindle_Count', 'Slow_Spindle_Count', 'Fast_Spindle_Count', ...
                'Spindle_Density_per_min_NREM', 'Mean_Frequency_Hz', 'Mean_Duration_ms', 'Topographical_Region'});

            for i = 1:nChannels
                channelIdx = channels(i);
                channelSpindles = obj.spindleEvents(obj.spindleEvents(:,7) == channelIdx, :);
                channelName = obj.channelLabels{channelIdx};

                channelSpindleTypes = spindleTypes(obj.spindleEvents(:,7) == channelIdx);

                channelStats.Channel{i} = channelName;
                channelStats.Total_Spindle_Count(i) = size(channelSpindles, 1);
                channelStats.Slow_Spindle_Count(i) = sum(strcmp(channelSpindleTypes, 'Slow'));
                channelStats.Fast_Spindle_Count(i) = sum(strcmp(channelSpindleTypes, 'Fast'));
                channelStats.Spindle_Density_per_min_NREM(i) = size(channelSpindles, 1) / totalNREMTime;
                channelStats.Mean_Frequency_Hz(i) = mean(channelSpindles(:,6));
                channelStats.Mean_Duration_ms(i) = mean(channelSpindles(:,5)) * 1000;

                if any(strcmp(frontalChannels, channelName))
                    channelStats.Topographical_Region{i} = 'Frontal';
                elseif any(strcmp(centralChannels, channelName))
                    channelStats.Topographical_Region{i} = 'Central';
                else
                    channelStats.Topographical_Region{i} = 'Other';
                end
            end

            % Sleep Stage Statistics - Focus on NREM stages
            stageStats = table();
            if ~isempty(obj.numericHypnogram)
                stages = [2, 3]; % N2, N3 (SWS)
                stageNames = {'N2', 'N3'};
                nStages = length(stages);

                stageStats = table('Size', [nStages, 6], ...
                    'VariableTypes', {'cell', 'double', 'double', 'double', 'double', 'double'}, ...
                    'VariableNames', {'Stage', 'Total_Spindle_Count', 'Slow_Spindle_Count', 'Fast_Spindle_Count', ...
                    'Stage_Duration_min', 'Spindle_Density_per_min'});

                for i = 1:nStages
                    stageDur = sum(obj.numericHypnogram == stages(i)) * 30 / 60;
                    stageTotal = obj.countSpindlesInStage(stages(i));
                    stageSlow = obj.countSpindlesInStageByType(stages(i), 'Slow');
                    stageFast = obj.countSpindlesInStageByType(stages(i), 'Fast');

                    stageStats.Stage{i} = stageNames{i};
                    stageStats.Total_Spindle_Count(i) = stageTotal;
                    stageStats.Slow_Spindle_Count(i) = stageSlow;
                    stageStats.Fast_Spindle_Count(i) = stageFast;
                    stageStats.Stage_Duration_min(i) = stageDur;
                    stageStats.Spindle_Density_per_min(i) = stageTotal / max(stageDur, 0.1);
                end
            end

            % Data Quality Metrics
            qualityStats = {
                'Total_Recording_Time_min', length(obj.data{1}) / obj.fs(1) / 60;
                'Artifact_Free_Percent', obj.cleaningSummary.cleanDataPercentage;
                'Artifact_Percent', obj.cleaningSummary.artifactPercentage;
                'ECG_Decontamination_Applied', obj.cleaningSummary.ecgDecontaminationApplied;
                'ECG_Contamination_Score', obj.cleaningSummary.ecgContaminationScore;
                'Total_Artifacts', obj.cleaningSummary.totalArtifacts;
                };

            qualityTable = cell2table(qualityStats, 'VariableNames', {'Parameter', 'Value'});

            %% 4. WRITE ALL SHEETS TO EXCEL
            fprintf('Writing to Excel file...\n');
            writetable(T, outputFile, 'Sheet', 'Individual_Spindles');
            writetable(globalTable, outputFile, 'Sheet', 'Global_Statistics');
            writetable(channelStats, outputFile, 'Sheet', 'Channel_Statistics');

            if ~isempty(SO_table)
                % Add cycle numbers to SO table if available
                if ~isempty(SO_cycleNumbers)
                    SO_table.CycleNumber = SO_cycleNumbers;
                end
                writetable(SO_table, outputFile, 'Sheet', 'Slow_Oscillations');
            end

            if ~isempty(stageStats) && height(stageStats) > 0
                writetable(stageStats, outputFile, 'Sheet', 'Stage_Statistics');
            end

            if ~isempty(cycleStats) && height(cycleStats) > 0
                writetable(cycleStats, outputFile, 'Sheet', 'Cycle_Statistics');
            end

            writetable(qualityTable, outputFile, 'Sheet', 'Data_Quality');

            fprintf('SUCCESS: Saved comprehensive Mölle method results to: %s\n', outputFile);
            fprintf('Sheets created:\n');
            fprintf('  - Individual_Spindles: %d spindle events\n', nSpindles);
            fprintf('  - Global_Statistics: Overall summary metrics\n');
            fprintf('  - Channel_Statistics: %d channels analyzed\n', nChannels);
            if ~isempty(SO_table)
                fprintf('  - Slow_Oscillations: %d SO events\n', SO_count);
            end
            if ~isempty(stageStats)
                fprintf('  - Stage_Statistics: Sleep stage distributions\n');
            end
            if ~isempty(cycleStats)
                fprintf('  - Cycle_Statistics: %d sleep cycles\n', nCycles);
            end
            fprintf('  - Data_Quality: Recording quality metrics\n');
        end

        function totalSleepTime = calculateTotalSleepTime(obj)
            if isempty(obj.numericHypnogram)
                totalSleepTime = length(obj.data{1}) / obj.fs(1) / 60;
                return;
            end

            sleepEpochs = sum(obj.numericHypnogram >= 1 & obj.numericHypnogram <= 5);
            totalSleepTime = sleepEpochs * 30 / 60;
        end

        function totalNREMTime = calculateNREMTime(obj)
            % Calculate NREM sleep time (N2 + N3/SWS) for Mölle method density calculations
            if isempty(obj.numericHypnogram)
                totalNREMTime = length(obj.data{1}) / obj.fs(1) / 60;
                return;
            end

            % Mölle et al. focused on N2 and SWS (stages 2, 3, 4)
            nremEpochs = sum(obj.numericHypnogram == 2 | obj.numericHypnogram == 3 | obj.numericHypnogram == 4);
            totalNREMTime = nremEpochs * 30 / 60;
        end

        function count = countSpindlesInStage(obj, stageNum)
            count = 0;
            for i = 1:size(obj.spindleEvents, 1)
                epochNumber = ceil(obj.spindleEvents(i,3) / 30);
                if epochNumber <= length(obj.numericHypnogram) && obj.numericHypnogram(epochNumber) == stageNum
                    count = count + 1;
                end
            end
        end

        function count = countSpindlesInStageByType(obj, stageNum, spindleType)
            count = 0;
            spindleTypes = obj.classifySpindleTypes();
            for i = 1:size(obj.spindleEvents, 1)
                epochNumber = ceil(obj.spindleEvents(i,3) / 30);
                if epochNumber <= length(obj.numericHypnogram) && ...
                        obj.numericHypnogram(epochNumber) == stageNum && ...
                        strcmp(spindleTypes{i}, spindleType)
                    count = count + 1;
                end
            end
        end

        function count = countSOsInStage(obj, stageNum)
            % Count SOs in specific sleep stage
            count = 0;
            if isempty(obj.SO_events)
                return;
            end

            for i = 1:size(obj.SO_events, 1)
                epochNumber = ceil(obj.SO_events(i,1) / 30);
                if epochNumber <= length(obj.numericHypnogram) && obj.numericHypnogram(epochNumber) == stageNum
                    count = count + 1;
                end
            end
        end

        function spindleTypes = classifySpindleTypes(obj)
            % Classify spindles as Slow or Fast based on topography and frequency
            nSpindles = size(obj.spindleEvents, 1);
            spindleTypes = cell(nSpindles, 1);

            frontalChannels = {'F3-M2', 'F4-M1', 'F3', 'F4', 'Fz', 'F1', 'F2'};
            centralChannels = {'C3-M2', 'C4-M1', 'C3', 'C4', 'Cz', 'C1', 'C2', 'P3', 'P4', 'Pz'};

            for i = 1:nSpindles
                chIdx = obj.spindleEvents(i,7);
                if chIdx <= length(obj.channelLabels)
                    channelName = obj.channelLabels{chIdx};
                    frequency = obj.spindleEvents(i,6);

                    if any(strcmp(frontalChannels, channelName))
                        spindleTypes{i} = 'Slow';
                    elseif any(strcmp(centralChannels, channelName))
                        spindleTypes{i} = 'Fast';
                    else
                        if frequency >= 11 && frequency < 13.5
                            spindleTypes{i} = 'Slow';
                        elseif frequency >= 13.5 && frequency <= 16
                            spindleTypes{i} = 'Fast';
                        else
                            spindleTypes{i} = 'Atypical';
                        end
                    end
                else
                    spindleTypes{i} = 'Unknown';
                end
            end
        end
    end

    methods (Access = private)
        function loadHypnogram(obj)
            try
                fprintf('Loading hypnogram: %s\n', obj.xmlPath);

                if ~exist(obj.xmlPath, 'file')
                    warning('XML file not found: %s', obj.xmlPath);
                    obj.numericHypnogram = [];
                    return;
                end

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
            catch ME
                warning('Hypnogram loading failed: %s', ME.message);
                obj.numericHypnogram = [];
            end
        end

        function setupMappedChannels(obj)
            fprintf('Setting up channels...\n');

            rawChannelNames = obj.edfLoader.signal_labels;

            fprintf('Raw channel names from EDF:\n');
            for i = 1:length(rawChannelNames)
                fprintf('  Channel %d: "%s"\n', i, rawChannelNames{i});
            end

            mappedNames = ChannelMappingHelper(rawChannelNames);
            obj.mappedChannelNames = rawChannelNames;
            obj.channelLabels = mappedNames;

            obj.data = obj.loadEDFData(1:length(rawChannelNames));

            % === KEY CHANGE: Get sampling rates for ALL channels ===
            obj.fs = obj.getSamplingRates();

            fprintf('Mapped %d channels\n', length(obj.channelLabels));
            fprintf('Sampling rates: %s Hz\n', mat2str(obj.fs));
        end

        function fs_array = getSamplingRates(obj)
            % === NEW METHOD: Get sampling rates for ALL channels ===
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

        function data = loadEDFData(obj, channelIndices)
            fprintf('Loading data for %d channels...\n', length(channelIndices));

            try
                signalCell = obj.edfLoader.edf.signalCell;
                data = cell(1, length(channelIndices));

                for i = 1:length(channelIndices)
                    channelData = signalCell{channelIndices(i)};
                    data{i} = double(channelData);
                end

                fprintf('Successfully loaded data for %d channels\n', length(data));

            catch ME
                fprintf('Error in data loading: %s\n', ME.message);
                rethrow(ME);
            end
        end

        function setDefaultParams(obj, p)
            dp = struct();
            dp.freqBand = [11 16];
            dp.duration = [0.5 3.0];
            dp.rmsWin = 0.2;
            dp.threshold = 2.0;
            dp.minInterval = 0.3;
            if isfield(p,'freqBand'), dp.freqBand = p.freqBand; end
            if isfield(p,'duration'), dp.duration = p.duration; end
            if isfield(p,'rmsWin'), dp.rmsWin = p.rmsWin; end
            if isfield(p,'threshold'), dp.threshold = p.threshold; end
            if isfield(p,'minInterval'), dp.minInterval = p.minInterval; end
            obj.detectionParams = dp;
        end

        function SO_events = detectSlowOscillations(obj)
            % Detect slow oscillations using Mölle et al. method - NREM sleep only
            SO_events = [];

            frontal_SO_channels = {'F3-M2', 'F4-M1', 'F3', 'F4', 'Fz'};

            available_channels = {};
            for ch = 1:length(frontal_SO_channels)
                if any(strcmp(obj.channelLabels, frontal_SO_channels{ch}))
                    available_channels{end+1} = frontal_SO_channels{ch};
                end
            end

            if isempty(available_channels)
                available_channels = obj.channelLabels(1:min(8, length(obj.channelLabels)));
            end

            for ch = 1:length(available_channels)
                channelName = available_channels{ch};
                chIdx = find(strcmp(obj.channelLabels, channelName));
                if isempty(chIdx), continue; end

                x = obj.data{chIdx};
                if isempty(x), continue; end

                % === KEY CHANGE: Use channel-specific sampling rate ===
                if length(obj.fs) >= chIdx
                    fs = obj.fs(chIdx);
                else
                    fs = obj.fs(1); % Fallback to first channel's rate
                end

                % Apply NREM sleep mask (stages 2, 3, 4)
                if ~isempty(obj.numericHypnogram)
                    samplesPerEpoch = 30 * fs; % Uses channel-specific SR
                    nremMask = false(1, length(x));

                    for epoch = 1:min(length(obj.numericHypnogram), ceil(length(x)/samplesPerEpoch))
                        stageNum = obj.numericHypnogram(epoch);
                        if stageNum == 2 || stageNum == 3 || stageNum == 4 % NREM sleep only
                            startSample = (epoch-1) * samplesPerEpoch + 1;
                            endSample = min(epoch * samplesPerEpoch, length(x));
                            nremMask(startSample:endSample) = true;
                        end
                    end
                    x = x(nremMask);
                end

                % Clean data - remove NaN/Inf values
                x = x(isfinite(x));
                if isempty(x) || length(x) < fs * 10
                    continue;
                end

                % Low-pass filter 30 Hz
                [b,a] = butter(2, 30/(fs/2), 'low');
                x_lp = filtfilt(b, a, x);

                % 3.5 Hz low-pass filter for SO detection
                [b,a] = butter(2, 3.5/(fs/2), 'low');
                x_so = filtfilt(b, a, x_lp);

                % Find positive-to-negative zero crossings
                zero_crossings = find(diff(sign(x_so)) == -2);

                for i = 1:length(zero_crossings)-1
                    start_idx = zero_crossings(i);
                    end_idx = zero_crossings(i+1);

                    duration = (end_idx - start_idx) / fs;
                    if duration < 0.9 || duration > 2.0
                        continue;
                    end

                    segment = x_so(start_idx:end_idx);
                    [neg_peak, neg_idx] = min(segment);
                    [pos_peak, pos_idx] = max(segment);

                    % Amplitude criteria (relaxed)
                    if neg_peak < -40 && (pos_peak - neg_peak) >= 70
                        peak_time = (start_idx + neg_idx - 1) / fs;
                        SO_events(end+1,:) = [peak_time, duration, neg_peak, chIdx];
                    end
                end
            end

            % Remove duplicates
            if ~isempty(SO_events)
                [~, unique_idx] = unique(SO_events(:,1), 'stable');
                SO_events = SO_events(unique_idx, :);
            end
        end

        function [slow_spindles, fast_spindles] = detectSpindlesMolleMethod(obj, sleepOnly)
            % Detect spindles with topography separation (Mölle method) - NREM sleep only
            slow_spindle_channels = {'F3-M2', 'F4-M1', 'F3', 'F4', 'Fz'};
            fast_spindle_channels = {'C3-M2', 'C4-M1', 'C3', 'C4', 'Cz', 'P3', 'P4', 'Pz'};

            % Find available channels
            available_slow = {};
            for ch = 1:length(slow_spindle_channels)
                if any(strcmp(obj.channelLabels, slow_spindle_channels{ch}))
                    available_slow{end+1} = slow_spindle_channels{ch};
                end
            end

            available_fast = {};
            for ch = 1:length(fast_spindle_channels)
                if any(strcmp(obj.channelLabels, fast_spindle_channels{ch}))
                    available_fast{end+1} = fast_spindle_channels{ch};
                end
            end

            % Use Mölle paper frequencies
            slow_peak_freq = 10.23;
            fast_peak_freq = 13.40;

            slow_spindles = [];
            fast_spindles = [];

            % Detect slow spindles in frontal channels
            for ch = 1:length(available_slow)
                channelName = available_slow{ch};
                chIdx = find(strcmp(obj.channelLabels, channelName));
                if isempty(chIdx), continue; end

                x = obj.data{chIdx};
                spindles = obj.detectSpindlesSingleChannel(x, channelName, slow_peak_freq, chIdx, sleepOnly);
                if ~isempty(spindles)
                    slow_spindles = [slow_spindles; spindles];
                end
            end

            % Detect fast spindles in central-parietal channels
            for ch = 1:length(available_fast)
                channelName = available_fast{ch};
                chIdx = find(strcmp(obj.channelLabels, channelName));
                if isempty(chIdx), continue; end

                x = obj.data{chIdx};
                spindles = obj.detectSpindlesSingleChannel(x, channelName, fast_peak_freq, chIdx, sleepOnly);
                if ~isempty(spindles)
                    fast_spindles = [fast_spindles; spindles];
                end
            end
        end

        function events = detectSpindlesSingleChannel(obj, x, channelName, center_freq, chIdx, sleepOnly)
            % Mölle method spindle detection for single channel - NREM sleep only

            % === KEY CHANGE: Use channel-specific sampling rate ===
            if length(obj.fs) >= chIdx
                fs = obj.fs(chIdx);
            else
                fs = obj.fs(1); % Fallback to first channel's rate
            end

            % Clean data first
            x = x(isfinite(x));
            if isempty(x) || length(x) < fs * 10
                events = [];
                return;
            end

            % Apply sleep restriction - Mölle method uses NREM sleep only (stages 2, 3, 4)
            if sleepOnly && ~isempty(obj.numericHypnogram)
                samplesPerEpoch = 30 * fs; % Uses channel-specific SR
                nremMask = false(1, length(x));

                for epoch = 1:min(length(obj.numericHypnogram), ceil(length(x)/samplesPerEpoch))
                    stageNum = obj.numericHypnogram(epoch);
                    if stageNum == 2 || stageNum == 3 || stageNum == 4 % NREM sleep only
                        startSample = (epoch-1) * samplesPerEpoch + 1;
                        endSample = min(epoch * samplesPerEpoch, length(x));
                        nremMask(startSample:endSample) = true;
                    end
                end
                x = x(nremMask);
            end

            if isempty(x) || length(x) < fs * 10
                events = [];
                return;
            end

            x = x - mean(x);
            if size(x, 1) > size(x, 2)
                x = x';
            end

            % Bandpass filter ±1.5 Hz around center frequency
            band_low = max(0.5, center_freq - 1.5);
            band_high = min(fs/2-1, center_freq + 1.5);

            try
                [b,a] = butter(2, [band_low, band_high]/(fs/2), 'bandpass');
                xf = filtfilt(b, a, x);
            catch
                events = [];
                return;
            end

            % RMS with 0.2s moving window
            win_samples = round(0.2 * fs);
            if win_samples > length(xf)
                events = [];
                return;
            end

            rms_env = sqrt(conv(xf.^2, ones(win_samples,1)/win_samples, 'same'));

            % Smooth RMS with 0.2s moving average
            rms_smooth = conv(rms_env, ones(win_samples,1)/win_samples, 'same');

            % Remove any remaining NaN/Inf values
            rms_smooth = rms_smooth(isfinite(rms_smooth));
            if isempty(rms_smooth)
                events = [];
                return;
            end

            % Threshold = 1.5 standard deviations
            threshold = 1.5 * std(rms_smooth);

            % Find threshold crossings
            above = rms_smooth > threshold;
            above = [false, above, false];

            d = diff(above);
            starts = find(d == 1);
            ends = find(d == -1) - 1;

            events = [];
            for i = 1:min(length(starts), length(ends))
                s = starts(i);
                e = ends(i);
                if e <= s, continue; end

                dur = (e - s) / fs;
                if dur < 0.5 || dur > 3.0
                    continue;
                end

                if e > length(xf) || s > length(xf)
                    continue;
                end

                spindle_segment = xf(s:e);
                [~, peak_idx] = min(spindle_segment);
                peak_sample = s + peak_idx - 1;

                if peak_sample > length(rms_smooth)
                    continue;
                end

                % Calculate actual frequency
                spindle_data = spindle_segment - mean(spindle_segment);
                [pks, locs] = findpeaks(spindle_data, 'MinPeakHeight', std(spindle_data)*0.3);

                if length(locs) >= 2
                    peak_intervals = diff(locs) / fs;
                    frequency = 1 / mean(peak_intervals);
                else
                    frequency = center_freq;
                end

                % Ensure frequency is within reasonable range
                if frequency < 8 || frequency > 20
                    frequency = center_freq;
                end

                events(end+1,:) = [s/fs, e/fs, peak_sample/fs, rms_smooth(peak_sample), dur, frequency, chIdx];
            end
        end

        function analyzeTemporalRelationships(obj)
            % Basic temporal relationship analysis
            obj.temporalRelations = struct();

            if isempty(obj.SO_events) || (isempty(obj.slow_spindles) && isempty(obj.fast_spindles))
                return;
            end

            SO_times = obj.SO_events(:,1);

            if ~isempty(obj.fast_spindles)
                fast_times = obj.fast_spindles(:,3);
                obj.temporalRelations.fast_spindle_count = length(fast_times);
            end

            if ~isempty(obj.slow_spindles)
                slow_times = obj.slow_spindles(:,3);
                obj.temporalRelations.slow_spindle_count = length(slow_times);
            end

            obj.temporalRelations.SO_count = length(SO_times);
        end
    end
end