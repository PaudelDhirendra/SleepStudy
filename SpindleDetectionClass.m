classdef SpindleDetectionClass < handle
    % SpindleDetectionClass: Enhanced sleep spindle detection using hierarchical fusion
    % OPTIMIZED: Consolidated channel statistics and topography analysis
    % ENHANCED: Integrated fast/slow spindle analysis into all metrics
    % ADDED: Comprehensive SO-spindle timing relationships in Excel output

    properties
        edfLoader
        fs                    % Array of sampling rates for each channel
        channelLabels
        data                  % Full data (will be trimmed to SPT)
        sptData              % Data trimmed to Sleep Period Time only
        spindleEvents      % Consolidated spindle events [start_s, end_s, peak_s, amplitude, duration_s, frequency_Hz, channel_idx]
        detectionParams
        edfPath
        xmlPath
        mappedChannelNames
        numericHypnogram
        stage2Mask
        stage3Mask
        artifactDetector
        cleaningSummary

        % SO detection properties
        SO_events          % Slow oscillation events [peak_time, duration, amplitude, channel_idx]
        temporalRelations  % SO-spindle timing relationships
        
        % Enhanced properties
        sleepCycles
        cycleStats
        channelStats
        
        % SPT properties
        sptStartEpoch
        sptEndEpoch
        sptStartSample
        sptEndSample
        sptDuration

        % Wavelet detection properties
        waveletParams
        consensusSpindles
        spindleQualityMetrics

        % Analysis results
        methodComparison
        fusionMetrics
        
        % Fast/Slow spindle properties
        fastSpindleEvents    % Fast spindles (13-16 Hz) [start_s, end_s, peak_s, amplitude, duration_s, frequency_Hz, channel_idx]
        slowSpindleEvents    % Slow spindles (11-13 Hz) [start_s, end_s, peak_s, amplitude, duration_s, frequency_Hz, channel_idx]
        
        % Stage statistics with channel and spindle type information
        stageStats
            stageStatsTable      
    cycleStatsTable      
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
            obj.setOptimizedParams(params);
            obj.spindleEvents = [];

            obj.artifactDetector = ArtifactDetectionClass();

            if nargin >= 3 && isfield(params, 'ecgName')
                obj.artifactDetector.setECGParameters(params.ecgName, params.denoiseEcg);
            end

            % Initialize properties
            obj.SO_events = [];
            obj.temporalRelations = struct();
            obj.sleepCycles = [];
            obj.cycleStats = struct();
            obj.channelStats = struct();

            % Initialize wavelet parameters
            obj.setOptimizedWaveletParams();
            obj.consensusSpindles = [];
            obj.spindleQualityMetrics = struct();

            % Initialize analysis results
            obj.methodComparison = struct();
            obj.fusionMetrics = struct();
            
            % Initialize SPT properties
            obj.sptData = {};
            obj.sptStartEpoch = 1;
            obj.sptEndEpoch = 1;
            obj.sptStartSample = 1;
            obj.sptEndSample = 1;
            obj.sptDuration = 0;
            
            % Initialize fast/slow spindle properties
            obj.fastSpindleEvents = [];
            obj.slowSpindleEvents = [];
            
            % Initialize stage statistics
            obj.stageStats = struct();
        end

        function runDetection(obj, channels, references, just2)
            % Main detection method using hierarchical fusion approach
            fprintf('Starting hierarchical fusion spindle detection...\n');
            fprintf('OPTIMIZATION: Processing only Sleep Period Time (SPT) to reduce compute resources.\n');

            % First, identify SPT and trim data
            obj.identifySleepPeriodTime();
            
            % Data cleaning ONLY on SPT data
            obj.performDataCleaningSPT(channels);

            % Set default parameters
            if nargin < 4
                just2 = true; % Default to NREM sleep only
            end
            if nargin < 3
                references = {};
            end

            % Run hierarchical fusion detection
            obj.runHierarchicalFusionSPT(channels, just2);
            
            % Perform comprehensive analysis
            obj.performEnhancedAnalysis();
            obj.performMethodComparison();
            obj.performConsolidatedChannelAnalysis();
               obj.performStageStatistics();      % NOW: Channel-stage breakdown
    obj.performCycleStatistics();      % NOW: Channel-cycle-stage breakdown
            
            fprintf('HIERARCHICAL FUSION DETECTION COMPLETED:\n');
            fprintf('  Consensus Spindles: %d\n', size(obj.spindleEvents, 1));
            fprintf('  Fast Spindles: %d\n', size(obj.fastSpindleEvents, 1));
            fprintf('  Slow Spindles: %d\n', size(obj.slowSpindleEvents, 1));
            fprintf('  Slow Oscillations: %d\n', size(obj.SO_events, 1));
        end

        function runHierarchicalFusionSPT(obj, channels, sleepOnly)
            % Hierarchical fusion detection based on Chen et al. 2023
            fprintf('Running hierarchical fusion spindle detection on SPT...\n');

            try
                % Step 1: Detect Slow Oscillations in NREM sleep
                fprintf('Detecting slow oscillations in NREM sleep (SPT only)...\n');
                obj.SO_events = obj.detectSlowOscillationsSPT();

                % Step 2: Run both detection methods independently
                fprintf('Running Morlet wavelet detection...\n');
                waveletSpindles = obj.detectWaveletSpindlesSPT(channels, sleepOnly);
                
                fprintf('Running RMS detection...\n');
                rmsSpindles = obj.detectRMSSpindlesSPT(channels, sleepOnly);

                % Step 3: Perform hierarchical fusion
                fprintf('Performing hierarchical fusion...\n');
                obj.spindleEvents = obj.performFusionDetection(waveletSpindles, rmsSpindles);

                % Classify spindle types
                obj.classifySpindleTypes();

                % Convert SPT-relative times to absolute times
                if ~isempty(obj.spindleEvents)
                    timeOffset = (obj.sptStartSample-1) / obj.fs(1);
                    obj.spindleEvents(:,1:3) = obj.spindleEvents(:,1:3) + timeOffset;
                end
                if ~isempty(obj.SO_events)
                    timeOffset = (obj.sptStartSample-1) / obj.fs(1);
                    obj.SO_events(:,1) = obj.SO_events(:,1) + timeOffset;
                end

                % Step 4: Analyze temporal relationships
                if ~isempty(obj.SO_events) && ~isempty(obj.spindleEvents)
                    fprintf('Analyzing temporal relationships...\n');
                    obj.analyzeTemporalRelationships();
                end

                % Step 5: Calculate method comparison statistics
                obj.calculateMethodComparison(waveletSpindles, rmsSpindles);

                fprintf('Hierarchical fusion detection completed (SPT only):\n');
                fprintf('  Slow oscillations: %d\n', size(obj.SO_events, 1));
                fprintf('  Consensus spindles: %d\n', size(obj.spindleEvents, 1));
                fprintf('  Fast spindles: %d\n', size(obj.fastSpindleEvents, 1));
                fprintf('  Slow spindles: %d\n', size(obj.slowSpindleEvents, 1));

            catch ME
                fprintf('Error in hierarchical fusion detection: %s\n', ME.message);
                obj.SO_events = [];
                obj.spindleEvents = [];
                obj.fastSpindleEvents = [];
                obj.slowSpindleEvents = [];
                rethrow(ME);
            end
        end

        function classifySpindleTypes(obj)
            % Classify spindles into fast (13-16 Hz) and slow (11-13 Hz) types
            fprintf('Classifying spindles into fast and slow types...\n');
            
            if isempty(obj.spindleEvents)
                obj.fastSpindleEvents = [];
                obj.slowSpindleEvents = [];
                return;
            end
            
            % Extract frequencies from spindle events (column 6 contains frequency)
            frequencies = obj.spindleEvents(:,6);
            
            % Classify spindles
            fastMask = frequencies >= 13 & frequencies <= 16;
            slowMask = frequencies >= 11 & frequencies < 13;
            
            obj.fastSpindleEvents = obj.spindleEvents(fastMask, :);
            obj.slowSpindleEvents = obj.spindleEvents(slowMask, :);
            
            fprintf('Spindle type classification:\n');
            fprintf('  Fast spindles (13-16 Hz): %d\n', size(obj.fastSpindleEvents, 1));
            fprintf('  Slow spindles (11-13 Hz): %d\n', size(obj.slowSpindleEvents, 1));
            fprintf('  Unclassified: %d\n', size(obj.spindleEvents, 1) - sum(fastMask) - sum(slowMask));
        end

        function performConsolidatedChannelAnalysis(obj)
    % Consolidated analysis with regional grouping (Frontal, Central only)
    fprintf('Performing consolidated channel analysis with regional grouping...\n');
    
    if isempty(obj.spindleEvents) && isempty(obj.SO_events)
        obj.channelStats = struct();
        return;
    end

    % Define channel groups by region (only Frontal and Central)
    frontal_channels = {'F3-M2', 'F4-M1', 'Fz'};
    central_channels = {'C3-M2', 'C4-M1', 'Cz'};
    
    stages = {'N1', 'N2', 'N3', 'REM'};
    
    % Initialize regional statistics
    stats = struct();
    
    % Process each region (only Frontal and Central)
    regions = {'Frontal', 'Central'};
    region_channels = {frontal_channels, central_channels};
    
    for region_idx = 1:length(regions)
        region_name = regions{region_idx};
        region_ch_list = region_channels{region_idx};
        
        % Find actual channels from available labels
        region_ch_indices = [];
        region_ch_names = {};
        
        for ch = 1:length(region_ch_list)
            ch_idx = find(strcmp(obj.channelLabels, region_ch_list{ch}));
            if ~isempty(ch_idx)
                region_ch_indices(end+1) = ch_idx;
                region_ch_names{end+1} = region_ch_list{ch};
            end
        end
        
        if isempty(region_ch_indices)
            continue;
        end
        
        % Initialize region statistics
        fieldName = ['region_' lower(region_name)];
        stats.(fieldName) = struct();
        stats.(fieldName).region_name = region_name;
        stats.(fieldName).channels = region_ch_names;
        stats.(fieldName).channel_indices = region_ch_indices;
        
        % Initialize totals
        stats.(fieldName).total_spindles = 0;
        stats.(fieldName).fast_spindles = 0;
        stats.(fieldName).slow_spindles = 0;
        stats.(fieldName).SO_count = 0;
        
        % Initialize stage-specific totals
        for stage_idx = 1:length(stages)
            stage = stages{stage_idx};
            stats.(fieldName).(['total_' stage]) = 0;
            stats.(fieldName).(['fast_' stage]) = 0;
            stats.(fieldName).(['slow_' stage]) = 0;
            stats.(fieldName).(['SO_' stage]) = 0;
        end
        
        % Initialize accumulators for means
        freq_accum = 0;
        dur_accum = 0;
        amp_accum = 0;
        fast_freq_accum = 0;
        slow_freq_accum = 0;
        
        % Count events for each channel in this region
        for ch_idx_idx = 1:length(region_ch_indices)
            channel_idx = region_ch_indices(ch_idx_idx);
            
            % Count total spindles and SOs for this channel
            if ~isempty(obj.spindleEvents)
                channel_spindles = obj.spindleEvents(obj.spindleEvents(:,7) == channel_idx, :);
                if ~isempty(channel_spindles)
                    stats.(fieldName).total_spindles = stats.(fieldName).total_spindles + size(channel_spindles, 1);
                    
                    % Count by type
                    fast_mask = channel_spindles(:,6) >= 13 & channel_spindles(:,6) <= 16;
                    slow_mask = channel_spindles(:,6) >= 11 & channel_spindles(:,6) < 13;
                    
                    stats.(fieldName).fast_spindles = stats.(fieldName).fast_spindles + sum(fast_mask);
                    stats.(fieldName).slow_spindles = stats.(fieldName).slow_spindles + sum(slow_mask);
                    
                    % Accumulate for means
                    freq_accum = freq_accum + sum(channel_spindles(:,6));
                    dur_accum = dur_accum + sum(channel_spindles(:,5));
                    amp_accum = amp_accum + sum(channel_spindles(:,4));
                    
                    if sum(fast_mask) > 0
                        fast_freq_accum = fast_freq_accum + sum(channel_spindles(fast_mask,6));
                    end
                    if sum(slow_mask) > 0
                        slow_freq_accum = slow_freq_accum + sum(channel_spindles(slow_mask,6));
                    end
                    
                    % Count by stage for this channel
                    for stage_idx = 1:length(stages)
                        stage = stages{stage_idx};
                        stageNum = obj.getStageNumber(stage);
                        
                        stage_spindles = 0;
                        stage_fast = 0;
                        stage_slow = 0;
                        
                        for i = 1:size(channel_spindles, 1)
                            epochNumber = ceil(channel_spindles(i,3) / 30);
                            if epochNumber <= length(obj.numericHypnogram) && ...
                               obj.numericHypnogram(epochNumber) == stageNum
                               
                                stage_spindles = stage_spindles + 1;
                                freq = channel_spindles(i,6);
                                if freq >= 13 && freq <= 16
                                    stage_fast = stage_fast + 1;
                                elseif freq >= 11 && freq < 13
                                    stage_slow = stage_slow + 1;
                                end
                            end
                        end
                        
                        stats.(fieldName).(['total_' stage]) = stats.(fieldName).(['total_' stage]) + stage_spindles;
                        stats.(fieldName).(['fast_' stage]) = stats.(fieldName).(['fast_' stage]) + stage_fast;
                        stats.(fieldName).(['slow_' stage]) = stats.(fieldName).(['slow_' stage]) + stage_slow;
                    end
                end
            end
            
            % Count SOs for this channel (mainly for Frontal region)
            if ~isempty(obj.SO_events)
                channel_SOs = obj.SO_events(obj.SO_events(:,4) == channel_idx, :);
                if ~isempty(channel_SOs)
                    stats.(fieldName).SO_count = stats.(fieldName).SO_count + size(channel_SOs, 1);
                    
                    % Count SOs by stage
                    for stage_idx = 1:length(stages)
                        stage = stages{stage_idx};
                        stageNum = obj.getStageNumber(stage);
                        
                        stage_SOs = 0;
                        for i = 1:size(channel_SOs, 1)
                            epochNumber = ceil(channel_SOs(i,1) / 30);
                            if epochNumber <= length(obj.numericHypnogram) && ...
                               obj.numericHypnogram(epochNumber) == stageNum
                                stage_SOs = stage_SOs + 1;
                            end
                        end
                        stats.(fieldName).(['SO_' stage]) = stats.(fieldName).(['SO_' stage]) + stage_SOs;
                    end
                end
            end
        end
        
        % Calculate means for the region
        if stats.(fieldName).total_spindles > 0
            stats.(fieldName).mean_frequency = freq_accum / stats.(fieldName).total_spindles;
            stats.(fieldName).mean_duration = dur_accum / stats.(fieldName).total_spindles;
            stats.(fieldName).mean_amplitude = amp_accum / stats.(fieldName).total_spindles;
        else
            stats.(fieldName).mean_frequency = 0;
            stats.(fieldName).mean_duration = 0;
            stats.(fieldName).mean_amplitude = 0;
        end
        
        if stats.(fieldName).fast_spindles > 0
            stats.(fieldName).fast_mean_freq = fast_freq_accum / stats.(fieldName).fast_spindles;
        else
            stats.(fieldName).fast_mean_freq = 0;
        end
        
        if stats.(fieldName).slow_spindles > 0
            stats.(fieldName).slow_mean_freq = slow_freq_accum / stats.(fieldName).slow_spindles;
        else
            stats.(fieldName).slow_mean_freq = 0;
        end
        
        % Calculate densities
        totalNREMTime = obj.calculateNREMTime();
        if totalNREMTime > 0
            stats.(fieldName).spindle_density = stats.(fieldName).total_spindles / totalNREMTime;
            stats.(fieldName).fast_density = stats.(fieldName).fast_spindles / totalNREMTime;
            stats.(fieldName).slow_density = stats.(fieldName).slow_spindles / totalNREMTime;
            stats.(fieldName).SO_density = stats.(fieldName).SO_count / totalNREMTime;
            
            % Calculate stage-specific densities
            stageDurations = obj.calculateStageDurations();
            for stage_idx = 1:length(stages)
                stage = stages{stage_idx};
                stage_duration = stageDurations.(stage);
                if stage_duration > 0
                    stats.(fieldName).([stage '_spindle_density']) = ...
                        stats.(fieldName).(['total_' stage]) / stage_duration;
                    stats.(fieldName).([stage '_fast_density']) = ...
                        stats.(fieldName).(['fast_' stage]) / stage_duration;
                    stats.(fieldName).([stage '_slow_density']) = ...
                        stats.(fieldName).(['slow_' stage]) / stage_duration;
                    stats.(fieldName).([stage '_SO_density']) = ...
                        stats.(fieldName).(['SO_' stage]) / stage_duration;
                else
                    stats.(fieldName).([stage '_spindle_density']) = 0;
                    stats.(fieldName).([stage '_fast_density']) = 0;
                    stats.(fieldName).([stage '_slow_density']) = 0;
                    stats.(fieldName).([stage '_SO_density']) = 0;
                end
            end
        else
            stats.(fieldName).spindle_density = 0;
            stats.(fieldName).fast_density = 0;
            stats.(fieldName).slow_density = 0;
            stats.(fieldName).SO_density = 0;
            for stage_idx = 1:length(stages)
                stage = stages{stage_idx};
                stats.(fieldName).([stage '_spindle_density']) = 0;
                stats.(fieldName).([stage '_fast_density']) = 0;
                stats.(fieldName).([stage '_slow_density']) = 0;
                stats.(fieldName).([stage '_SO_density']) = 0;
            end
        end
    end
    
    obj.channelStats = stats;
    
    % Print summary
    fprintf('Regional Channel Analysis (Frontal & Central only):\n');
    fieldNames = fieldnames(stats);
    for i = 1:length(fieldNames)
        fieldName = fieldNames{i};
        regionData = stats.(fieldName);
        fprintf('  %s: Total:%d (Fast:%d, Slow:%d) SO:%d\n', ...
            regionData.region_name, regionData.total_spindles, regionData.fast_spindles, ...
            regionData.slow_spindles, regionData.SO_count);
        fprintf('    Channels: %s\n', strjoin(regionData.channels, ', '));
        for stage_idx = 1:length(stages)
            stage = stages{stage_idx};
            fprintf('    %s: %d spindles\n', stage, regionData.(['total_' stage]));
        end
    end
end

        function performStageStatistics(obj)
    % Stage statistics with channel breakdown AND totals
    fprintf('Performing stage statistics by channel with totals...\n');
    
    obj.stageStats = struct();
    
    if isempty(obj.spindleEvents)
        fprintf('No spindle events found for stage statistics\n');
        return;
    end
    
    % Get all channels that have spindles
    spindle_channels = unique(obj.spindleEvents(:,7));
    stages = {'N1', 'N2', 'N3', 'REM'};
    
    % Calculate stage durations (same for all channels)
    stageDurations = obj.calculateStageDurations();
    
    % Initialize data structure
    data = {};
    
    % FIRST: Add channel-specific stage statistics
    for chIdx = 1:length(spindle_channels)
        channelIdx = spindle_channels(chIdx);
        if channelIdx <= length(obj.channelLabels)
            chName = obj.channelLabels{channelIdx};
            
            for stageIdx = 1:length(stages)
                stage = stages{stageIdx};
                stageNum = obj.getStageNumber(stage);
                
                % Count spindles for this channel-stage combination
                [spindle_count, fast_count, slow_count, mean_freq, mean_dur, mean_amp] = ...
                    obj.countSpindlesInChannelStage(channelIdx, stageNum);
                
                % Calculate statistics
                stage_duration = stageDurations.(stage);
                spindle_density = 0;
                fast_density = 0;
                slow_density = 0;
                
                if stage_duration > 0
                    spindle_density = spindle_count / stage_duration;
                    fast_density = fast_count / stage_duration;
                    slow_density = slow_count / stage_duration;
                end
                
                % Add to data table (only if there are spindles)
                if spindle_count > 0
                    data{end+1, 1} = chName;
                    data{end, 2} = stage;
                    data{end, 3} = spindle_count;
                    data{end, 4} = fast_count;
                    data{end, 5} = slow_count;
                    data{end, 6} = stage_duration;
                    data{end, 7} = spindle_density;
                    data{end, 8} = fast_density;
                    data{end, 9} = slow_density;
                    data{end, 10} = mean_freq;
                    data{end, 11} = mean_dur;
                    data{end, 12} = mean_amp;
                end
            end
        end
    end
    
    % SECOND: Add TOTALS for each stage (across all channels)
    for stageIdx = 1:length(stages)
        stage = stages{stageIdx};
        stageNum = obj.getStageNumber(stage);
        
        total_spindles = 0;
        total_fast = 0;
        total_slow = 0;
        total_freq_accum = 0;
        total_dur_accum = 0;
        total_amp_accum = 0;
        
        % Sum across all channels for this stage
        for chIdx = 1:length(spindle_channels)
            channelIdx = spindle_channels(chIdx);
            [spindle_count, fast_count, slow_count, mean_freq, mean_dur, mean_amp] = ...
                obj.countSpindlesInChannelStage(channelIdx, stageNum);
            
            total_spindles = total_spindles + spindle_count;
            total_fast = total_fast + fast_count;
            total_slow = total_slow + slow_count;
            total_freq_accum = total_freq_accum + (mean_freq * spindle_count);
            total_dur_accum = total_dur_accum + (mean_dur * spindle_count);
            total_amp_accum = total_amp_accum + (mean_amp * spindle_count);
        end
        
        % Calculate averages for totals
        mean_freq_total = 0;
        mean_dur_total = 0;
        mean_amp_total = 0;
        
        if total_spindles > 0
            mean_freq_total = total_freq_accum / total_spindles;
            mean_dur_total = total_dur_accum / total_spindles;
            mean_amp_total = total_amp_accum / total_spindles;
        end
        
        stage_duration = stageDurations.(stage);
        spindle_density_total = 0;
        fast_density_total = 0;
        slow_density_total = 0;
        
        if stage_duration > 0
            spindle_density_total = total_spindles / stage_duration;
            fast_density_total = total_fast / stage_duration;
            slow_density_total = total_slow / stage_duration;
        end
        
        % Add TOTAL row for this stage
        if total_spindles > 0
            data{end+1, 1} = 'TOTAL';
            data{end, 2} = stage;
            data{end, 3} = total_spindles;
            data{end, 4} = total_fast;
            data{end, 5} = total_slow;
            data{end, 6} = stage_duration;
            data{end, 7} = spindle_density_total;
            data{end, 8} = fast_density_total;
            data{end, 9} = slow_density_total;
            data{end, 10} = mean_freq_total;
            data{end, 11} = mean_dur_total;
            data{end, 12} = mean_amp_total;
        end
    end
    
    % Store as table directly
    if isempty(data)
        obj.stageStatsTable = table();
    else
        obj.stageStatsTable = cell2table(data, 'VariableNames', {
            'Channel', 'Stage', 'Total_Spindles', 'Fast_Spindles', 'Slow_Spindles', ...
            'Stage_Duration_min', 'Spindle_Density_perMin', 'Fast_Density_perMin', ...
            'Slow_Density_perMin', 'Mean_Frequency_Hz', 'Mean_Duration_s', 'Mean_Amplitude'
            });
    end
    
    fprintf('Stage statistics completed: %d rows (channel breakdown + totals)\n', size(data, 1));
end

function performCycleStatistics(obj)
    % Cycle statistics with channel-stage breakdown AND totals
    fprintf('Performing cycle statistics by channel and stage with totals...\n');
    
    if isempty(obj.spindleEvents) || isempty(obj.sleepCycles) || isempty(obj.numericHypnogram)
        fprintf('Insufficient data for cycle statistics\n');
        obj.cycleStatsTable = table();
        return;
    end
    
    uniqueCycles = unique(obj.sleepCycles(obj.sleepCycles > 0));
    spindle_channels = unique(obj.spindleEvents(:,7));
    stages = {'N1', 'N2', 'N3', 'REM'};
    
    data = {};
    
    for cycleIdx = 1:length(uniqueCycles)
        cycleNum = uniqueCycles(cycleIdx);
        cycleEpochs = find(obj.sleepCycles == cycleNum);
        cycleDuration = length(cycleEpochs) * 0.5; % minutes
        
        % Calculate stage durations within this cycle
        cycleStageDurations = obj.calculateCycleStageDurations(cycleEpochs);
        
        % FIRST: Add channel-stage specific statistics for this cycle
        for chIdx = 1:length(spindle_channels)
            channelIdx = spindle_channels(chIdx);
            if channelIdx <= length(obj.channelLabels)
                chName = obj.channelLabels{channelIdx};
                
                for stageIdx = 1:length(stages)
                    stage = stages{stageIdx};
                    stageNum = obj.getStageNumber(stage);
                    
                    % Count spindles for this channel-cycle-stage combination
                    [spindle_count, fast_count, slow_count, mean_freq, mean_dur, mean_amp] = ...
                        obj.countSpindlesInChannelCycleStage(channelIdx, cycleEpochs, stageNum);
                    
                    % Calculate statistics
                    stage_duration = cycleStageDurations.(stage);
                    spindle_density = 0;
                    fast_density = 0;
                    slow_density = 0;
                    
                    if stage_duration > 0
                        spindle_density = spindle_count / stage_duration;
                        fast_density = fast_count / stage_duration;
                        slow_density = slow_count / stage_duration;
                    end
                    
                    % Add to data table (only if there are spindles or meaningful duration)
                    if spindle_count > 0 || stage_duration > 1.0
                        data{end+1, 1} = cycleNum;
                        data{end, 2} = chName;
                        data{end, 3} = stage;
                        data{end, 4} = spindle_count;
                        data{end, 5} = fast_count;
                        data{end, 6} = slow_count;
                        data{end, 7} = stage_duration;
                        data{end, 8} = spindle_density;
                        data{end, 9} = fast_density;
                        data{end, 10} = slow_density;
                        data{end, 11} = mean_freq;
                        data{end, 12} = mean_dur;
                        data{end, 13} = mean_amp;
                        data{end, 14} = cycleDuration;
                    end
                end
            end
        end
        
        % SECOND: Add TOTALS for each stage in this cycle (across all channels)
        for stageIdx = 1:length(stages)
            stage = stages{stageIdx};
            stageNum = obj.getStageNumber(stage);
            
            total_spindles = 0;
            total_fast = 0;
            total_slow = 0;
            total_freq_accum = 0;
            total_dur_accum = 0;
            total_amp_accum = 0;
            
            % Sum across all channels for this stage in this cycle
            for chIdx = 1:length(spindle_channels)
                channelIdx = spindle_channels(chIdx);
                [spindle_count, fast_count, slow_count, mean_freq, mean_dur, mean_amp] = ...
                    obj.countSpindlesInChannelCycleStage(channelIdx, cycleEpochs, stageNum);
                
                total_spindles = total_spindles + spindle_count;
                total_fast = total_fast + fast_count;
                total_slow = total_slow + slow_count;
                total_freq_accum = total_freq_accum + (mean_freq * spindle_count);
                total_dur_accum = total_dur_accum + (mean_dur * spindle_count);
                total_amp_accum = total_amp_accum + (mean_amp * spindle_count);
            end
            
            % Calculate averages for totals
            mean_freq_total = 0;
            mean_dur_total = 0;
            mean_amp_total = 0;
            
            if total_spindles > 0
                mean_freq_total = total_freq_accum / total_spindles;
                mean_dur_total = total_dur_accum / total_spindles;
                mean_amp_total = total_amp_accum / total_spindles;
            end
            
            stage_duration = cycleStageDurations.(stage);
            spindle_density_total = 0;
            fast_density_total = 0;
            slow_density_total = 0;
            
            if stage_duration > 0
                spindle_density_total = total_spindles / stage_duration;
                fast_density_total = total_fast / stage_duration;
                slow_density_total = total_slow / stage_duration;
            end
            
            % Add TOTAL row for this stage in this cycle
            if total_spindles > 0 || stage_duration > 1.0
                data{end+1, 1} = cycleNum;
                data{end, 2} = 'TOTAL';
                data{end, 3} = stage;
                data{end, 4} = total_spindles;
                data{end, 5} = total_fast;
                data{end, 6} = total_slow;
                data{end, 7} = stage_duration;
                data{end, 8} = spindle_density_total;
                data{end, 9} = fast_density_total;
                data{end, 10} = slow_density_total;
                data{end, 11} = mean_freq_total;
                data{end, 12} = mean_dur_total;
                data{end, 13} = mean_amp_total;
                data{end, 14} = cycleDuration;
            end
        end
    end
    
    % Store as table directly
    if isempty(data)
        obj.cycleStatsTable = table();
    else
        obj.cycleStatsTable = cell2table(data, 'VariableNames', {
            'Cycle', 'Channel', 'Stage', 'Total_Spindles', 'Fast_Spindles', 'Slow_Spindles', ...
            'Stage_Duration_min', 'Spindle_Density_perMin', 'Fast_Density_perMin', ...
            'Slow_Density_perMin', 'Mean_Frequency_Hz', 'Mean_Duration_s', 'Mean_Amplitude', ...
            'Cycle_Duration_min'
            });
    end
    
    fprintf('Cycle statistics completed: %d rows (channel-stage breakdown + totals)\n', size(data, 1));
end
function stageDurations = calculateStageDurations(obj)
    % Calculate stage durations in minutes for all sleep stages
    stageDurations = struct();
    
    if isempty(obj.numericHypnogram)
        % If no hypnogram, return zeros
        stages = {'N1', 'N2', 'N3', 'REM'};
        for i = 1:length(stages)
            stageDurations.(stages{i}) = 0;
        end
        return;
    end
    
    % Get SPT hypnogram
    sptHypnogram = obj.getSPTHypnogram();
    
    % Count epochs for each stage (each epoch is 30 seconds = 0.5 minutes)
    stageDurations.N1 = sum(sptHypnogram == 1) * 0.5;
    stageDurations.N2 = sum(sptHypnogram == 2) * 0.5;
    stageDurations.N3 = sum(sptHypnogram == 3) * 0.5;
    stageDurations.REM = sum(sptHypnogram == 5) * 0.5;
end

function cycleStageDurations = calculateCycleStageDurations(obj, cycleEpochs)
    % Calculate stage durations within a specific cycle
    cycleStageDurations = struct();
    
    if isempty(obj.numericHypnogram) || isempty(cycleEpochs)
        stages = {'N1', 'N2', 'N3', 'REM'};
        for i = 1:length(stages)
            cycleStageDurations.(stages{i}) = 0;
        end
        return;
    end
    
    % Get stages for the cycle epochs
    cycleStages = obj.numericHypnogram(cycleEpochs);
    
    % Count epochs for each stage (each epoch is 30 seconds = 0.5 minutes)
    cycleStageDurations.N1 = sum(cycleStages == 1) * 0.5;
    cycleStageDurations.N2 = sum(cycleStages == 2) * 0.5;
    cycleStageDurations.N3 = sum(cycleStages == 3) * 0.5;
    cycleStageDurations.REM = sum(cycleStages == 5) * 0.5;
end

% Helper functions for counting spindles
function [spindle_count, fast_count, slow_count, mean_freq, mean_dur, mean_amp] = countSpindlesInChannelStage(obj, channelIdx, stageNum)
    % Count spindles for a specific channel and stage
    spindle_count = 0;
    fast_count = 0;
    slow_count = 0;
    freq_accum = 0;
    dur_accum = 0;
    amp_accum = 0;
    
    for i = 1:size(obj.spindleEvents, 1)
        spindle = obj.spindleEvents(i, :);
        if spindle(7) == channelIdx
            epochNumber = ceil(spindle(3) / 30);
            if epochNumber <= length(obj.numericHypnogram) && ...
               obj.numericHypnogram(epochNumber) == stageNum
                
                spindle_count = spindle_count + 1;
                freq = spindle(6);
                freq_accum = freq_accum + freq;
                dur_accum = dur_accum + spindle(5);
                amp_accum = amp_accum + spindle(4);
                
                if freq >= 13 && freq <= 16
                    fast_count = fast_count + 1;
                elseif freq >= 11 && freq < 13
                    slow_count = slow_count + 1;
                end
            end
        end
    end
    
    % Calculate means
    mean_freq = 0;
    mean_dur = 0;
    mean_amp = 0;
    if spindle_count > 0
        mean_freq = freq_accum / spindle_count;
        mean_dur = dur_accum / spindle_count;
        mean_amp = amp_accum / spindle_count;
    end
end

function [spindle_count, fast_count, slow_count, mean_freq, mean_dur, mean_amp] = countSpindlesInChannelCycleStage(obj, channelIdx, cycleEpochs, stageNum)
    % Count spindles for a specific channel, cycle, and stage
    spindle_count = 0;
    fast_count = 0;
    slow_count = 0;
    freq_accum = 0;
    dur_accum = 0;
    amp_accum = 0;
    
    for i = 1:size(obj.spindleEvents, 1)
        spindle = obj.spindleEvents(i, :);
        if spindle(7) == channelIdx
            epochNumber = ceil(spindle(3) / 30);
            if ismember(epochNumber, cycleEpochs) && ...
               epochNumber <= length(obj.numericHypnogram) && ...
               obj.numericHypnogram(epochNumber) == stageNum
                
                spindle_count = spindle_count + 1;
                freq = spindle(6);
                freq_accum = freq_accum + freq;
                dur_accum = dur_accum + spindle(5);
                amp_accum = amp_accum + spindle(4);
                
                if freq >= 13 && freq <= 16
                    fast_count = fast_count + 1;
                elseif freq >= 11 && freq < 13
                    slow_count = slow_count + 1;
                end
            end
        end
    end
    
    % Calculate means
    mean_freq = 0;
    mean_dur = 0;
    mean_amp = 0;
    if spindle_count > 0
        mean_freq = freq_accum / spindle_count;
        mean_dur = dur_accum / spindle_count;
        mean_amp = amp_accum / spindle_count;
    end
end

        function channelDist = getChannelDistributionInStage(obj, stageNum)
            % Get spindle distribution across channels for a specific stage
            channelDist = struct();
            
            if isempty(obj.spindleEvents)
                return;
            end
            
            % Get all channels that have spindles in this stage
            channelsInStage = [];
            for i = 1:size(obj.spindleEvents, 1)
                epochNumber = ceil(obj.spindleEvents(i,3) / 30);
                if epochNumber <= length(obj.numericHypnogram) && obj.numericHypnogram(epochNumber) == stageNum
                    chIdx = obj.spindleEvents(i,7);
                    if chIdx <= length(obj.channelLabels)
                        chName = obj.channelLabels{chIdx};
                        if obj.isEEGChannel(chName)
                            channelsInStage(end+1) = chIdx;
                        end
                    end
                end
            end
            
            channelsInStage = unique(channelsInStage);
            
            for i = 1:length(channelsInStage)
                chIdx = channelsInStage(i);
                chName = obj.channelLabels{chIdx};
                fieldName = ['channel_' num2str(chIdx)];
                
                channelDist.(fieldName) = struct();
                channelDist.(fieldName).name = chName;
                channelDist.(fieldName).total_spindles = 0;
                channelDist.(fieldName).fast_spindles = 0;
                channelDist.(fieldName).slow_spindles = 0;
                
                % Count spindles in this stage for this channel
                for j = 1:size(obj.spindleEvents, 1)
                    epochNumber = ceil(obj.spindleEvents(j,3) / 30);
                    if epochNumber <= length(obj.numericHypnogram) && ...
                       obj.numericHypnogram(epochNumber) == stageNum && ...
                       obj.spindleEvents(j,7) == chIdx
                       
                        channelDist.(fieldName).total_spindles = channelDist.(fieldName).total_spindles + 1;
                        
                        freq = obj.spindleEvents(j,6);
                        if freq >= 13 && freq <= 16
                            channelDist.(fieldName).fast_spindles = channelDist.(fieldName).fast_spindles + 1;
                        elseif freq >= 11 && freq < 13
                            channelDist.(fieldName).slow_spindles = channelDist.(fieldName).slow_spindles + 1;
                        end
                    end
                end
            end
        end

        function count = countFastSpindlesInStage(obj, stageNum)
            % Count fast spindles in specific sleep stage
            count = 0;
            
            if isempty(obj.fastSpindleEvents)
                return;
            end

            for i = 1:size(obj.fastSpindleEvents, 1)
                epochNumber = ceil(obj.fastSpindleEvents(i,3) / 30);
                if epochNumber <= length(obj.numericHypnogram) && obj.numericHypnogram(epochNumber) == stageNum
                    count = count + 1;
                end
            end
        end

        function count = countSlowSpindlesInStage(obj, stageNum)
            % Count slow spindles in specific sleep stage
            count = 0;
            
            if isempty(obj.slowSpindleEvents)
                return;
            end

            for i = 1:size(obj.slowSpindleEvents, 1)
                epochNumber = ceil(obj.slowSpindleEvents(i,3) / 30);
                if epochNumber <= length(obj.numericHypnogram) && obj.numericHypnogram(epochNumber) == stageNum
                    count = count + 1;
                end
            end
        end

        function isEEG = isEEGChannel(~, channelName)
            % Check if channel is an EEG channel
            eeg_patterns = {'F3', 'F4', 'C3', 'C4', 'O1', 'O2', 'Fz', 'Cz', 'Pz', 'Oz', 'EEG'};
            isEEG = false;
            for pattern = eeg_patterns
                if contains(channelName, pattern{1})
                    isEEG = true;
                    break;
                end
            end
        end

        function analyzeTemporalRelationships(obj)
            % Comprehensive temporal relationship analysis between SOs and spindles
            fprintf('Analyzing SO-spindle temporal relationships...\n');
            
            obj.temporalRelations = struct();

            if isempty(obj.SO_events) || isempty(obj.spindleEvents)
                fprintf('  Not enough data for temporal analysis\n');
                return;
            end

            SO_times = obj.SO_events(:,1);
            spindle_times = obj.spindleEvents(:,3);
            spindle_frequencies = obj.spindleEvents(:,6);

            obj.temporalRelations.SO_count = length(SO_times);
            obj.temporalRelations.spindle_count = length(spindle_times);
            obj.temporalRelations.fast_spindle_count = sum(spindle_frequencies >= 13 & spindle_frequencies <= 16);
            obj.temporalRelations.slow_spindle_count = sum(spindle_frequencies >= 11 & spindle_frequencies < 13);
            
            % Find nearest SO for each spindle and calculate timing
            time_differences = zeros(size(spindle_times));
            nearest_SO_times = zeros(size(spindle_times));
            coupling_strengths = zeros(size(spindle_times));
            
            for i = 1:length(spindle_times)
                [min_time_diff, idx] = min(abs(SO_times - spindle_times(i)));
                time_differences(i) = spindle_times(i) - SO_times(idx);
                nearest_SO_times(i) = SO_times(idx);
                
                % Simple coupling strength based on temporal proximity
                coupling_strengths(i) = exp(-abs(min_time_diff) / 0.5); % 0.5s time constant
            end
            
            obj.temporalRelations.time_differences = time_differences;
            obj.temporalRelations.nearest_SO_times = nearest_SO_times;
            obj.temporalRelations.coupling_strengths = coupling_strengths;
            
            % Calculate statistics
            obj.temporalRelations.mean_time_diff = mean(time_differences);
            obj.temporalRelations.std_time_diff = std(time_differences);
            obj.temporalRelations.median_time_diff = median(time_differences);
            obj.temporalRelations.mean_coupling_strength = mean(coupling_strengths);
            
            % Categorize coupling
            early_coupled = sum(time_differences < -1.0); % Spindles >1s before SO peak
            late_coupled = sum(time_differences > 1.0);   % Spindles >1s after SO peak
            tightly_coupled = sum(abs(time_differences) <= 1.0); % Spindles within ±1s of SO peak
            
            obj.temporalRelations.early_coupled_count = early_coupled;
            obj.temporalRelations.late_coupled_count = late_coupled;
            obj.temporalRelations.tightly_coupled_count = tightly_coupled;
            obj.temporalRelations.early_coupled_percent = (early_coupled / length(time_differences)) * 100;
            obj.temporalRelations.late_coupled_percent = (late_coupled / length(time_differences)) * 100;
            obj.temporalRelations.tightly_coupled_percent = (tightly_coupled / length(time_differences)) * 100;
            
            % Fast vs slow spindle coupling differences
            fast_mask = spindle_frequencies >= 13 & spindle_frequencies <= 16;
            slow_mask = spindle_frequencies >= 11 & spindle_frequencies < 13;
            
            if sum(fast_mask) > 0
                obj.temporalRelations.fast_mean_time_diff = mean(time_differences(fast_mask));
                obj.temporalRelations.fast_mean_coupling = mean(coupling_strengths(fast_mask));
            else
                obj.temporalRelations.fast_mean_time_diff = 0;
                obj.temporalRelations.fast_mean_coupling = 0;
            end
            
            if sum(slow_mask) > 0
                obj.temporalRelations.slow_mean_time_diff = mean(time_differences(slow_mask));
                obj.temporalRelations.slow_mean_coupling = mean(coupling_strengths(slow_mask));
            else
                obj.temporalRelations.slow_mean_time_diff = 0;
                obj.temporalRelations.slow_mean_coupling = 0;
            end
            
            fprintf('Temporal Relationship Analysis:\n');
            fprintf('  Total SO-spindle pairs: %d\n', length(time_differences));
            fprintf('  Mean time difference: %.3f ± %.3f s\n', ...
                obj.temporalRelations.mean_time_diff, obj.temporalRelations.std_time_diff);
            fprintf('  Tightly coupled (±1s): %d (%.1f%%)\n', ...
                tightly_coupled, obj.temporalRelations.tightly_coupled_percent);
            fprintf('  Fast spindle coupling: %.3f s\n', obj.temporalRelations.fast_mean_time_diff);
            fprintf('  Slow spindle coupling: %.3f s\n', obj.temporalRelations.slow_mean_time_diff);
        end

        % KEEP ALL ORIGINAL DETECTION METHODS EXACTLY AS THEY WERE
        function consensusSpindles = performFusionDetection(obj, waveletSpindles, rmsSpindles)
            % Perform hierarchical fusion of wavelet and RMS detections
            
            fprintf('Performing hierarchical fusion with improved k-means...\n');
            
            if isempty(waveletSpindles) && isempty(rmsSpindles)
                consensusSpindles = [];
                return;
            end

            % Step 1: Identify coincident spindles (high confidence)
            [coincidentSpindles, nonCoincidentWavelet, nonCoincidentRMS] = ...
                obj.identifyCoincidentSpindles(waveletSpindles, rmsSpindles);
            
            fprintf('  Coincident spindles: %d\n', size(coincidentSpindles, 1));
            fprintf('  Non-coincident wavelet: %d\n', size(nonCoincidentWavelet, 1));
            fprintf('  Non-coincident RMS: %d\n', size(nonCoincidentRMS, 1));

            % Step 2: Directly accept coincident spindles
            consensusSpindles = coincidentSpindles;

            % Step 3: Cluster non-coincident spindles using improved k-means
            if ~isempty(nonCoincidentWavelet) || ~isempty(nonCoincidentRMS)
                clusteredSpindles = obj.improvedKMeansClustering(...
                    nonCoincidentWavelet, nonCoincidentRMS);
                
                fprintf('  Clustered spindles: %d\n', size(clusteredSpindles, 1));
                
                % Step 4: Combine results
                consensusSpindles = [consensusSpindles; clusteredSpindles];
            end

            % Remove duplicates based on timing and channel
            if ~isempty(consensusSpindles)
                consensusSpindles = obj.removeDuplicateSpindles(consensusSpindles);
            end

            fprintf('Hierarchical fusion completed: %d total consensus spindles\n', ...
                size(consensusSpindles, 1));
        end

        function [coincident, nonCoincidentWavelet, nonCoincidentRMS] = identifyCoincidentSpindles(obj, waveletSpindles, rmsSpindles)
            % Identify spindles detected by both methods (coincident)
            coincident = [];
            nonCoincidentWavelet = [];
            nonCoincidentRMS = [];
            
            if isempty(waveletSpindles) || isempty(rmsSpindles)
                nonCoincidentWavelet = waveletSpindles;
                nonCoincidentRMS = rmsSpindles;
                return;
            end
            
            matchTolerance = 1.0; % 1 second tolerance
            
            matchedWavelet = false(size(waveletSpindles, 1), 1);
            matchedRMS = false(size(rmsSpindles, 1), 1);
            
            for i = 1:size(waveletSpindles, 1)
                waveletSpindle = waveletSpindles(i, :);
                waveletChannel = waveletSpindle(7);
                waveletStart = waveletSpindle(1);
                waveletEnd = waveletSpindle(2);
                
                % Find matching RMS spindles on same channel
                sameChannel = rmsSpindles(:, 7) == waveletChannel;
                if ~any(sameChannel)
                    continue;
                end
                
                channelRMS = rmsSpindles(sameChannel, :);
                rmsIndices = find(sameChannel);
                
                % Check for temporal overlap
                for j = 1:size(channelRMS, 1)
                    rmsSpindle = channelRMS(j, :);
                    rmsStart = rmsSpindle(1);
                    rmsEnd = rmsSpindle(2);
                    
                    % Check if spindles overlap in time
                    overlap = obj.checkTemporalOverlap(waveletStart, waveletEnd, rmsStart, rmsEnd, matchTolerance);
                    
                    if overlap
                        % Create fused spindle (prefer wavelet timing, RMS amplitude)
                        fusedSpindle = zeros(1, 7);
                        fusedSpindle(1:2) = waveletSpindle(1:2); % Use wavelet timing
                        fusedSpindle(3) = mean([waveletSpindle(3), rmsSpindle(3)]); % Average peak time
                        fusedSpindle(4) = rmsSpindle(4); % Use RMS amplitude (more stable)
                        fusedSpindle(5) = mean([waveletSpindle(5), rmsSpindle(5)]); % Average duration
                        fusedSpindle(6) = waveletSpindle(6); % Use wavelet frequency (more accurate)
                        fusedSpindle(7) = waveletChannel; % Channel index
                        
                        coincident(end+1, :) = fusedSpindle;
                        matchedWavelet(i) = true;
                        matchedRMS(rmsIndices(j)) = true;
                        break;
                    end
                end
            end
            
            % Collect non-coincident spindles
            nonCoincidentWavelet = waveletSpindles(~matchedWavelet, :);
            nonCoincidentRMS = rmsSpindles(~matchedRMS, :);
        end

        function overlap = checkTemporalOverlap(obj, start1, end1, start2, end2, tolerance)
            % Check if two time intervals overlap within tolerance
            overlap = (start1 <= end2 + tolerance) && (end1 >= start2 - tolerance);
        end

        function clusteredSpindles = improvedKMeansClustering(obj, waveletSpindles, rmsSpindles)
            % Cluster non-coincident spindles using improved k-means
            
            if isempty(waveletSpindles) && isempty(rmsSpindles)
                clusteredSpindles = [];
                return;
            end
            
            % Combine non-coincident spindles
            allSpindles = [waveletSpindles; rmsSpindles];
            
            if size(allSpindles, 1) < 5
                clusteredSpindles = allSpindles;
                return;
            end
            
            % Extract features for clustering
            amplitudes = allSpindles(:, 4);
            frequencies = allSpindles(:, 6);
            durations = allSpindles(:, 5);
            
            % Normalize features
            features = [amplitudes / max(amplitudes), ...
                       frequencies / max(frequencies), ...
                       durations / max(durations)];
            
            % Remove outliers
            cleanFeatures = obj.removeAmplitudeOutliers(features, amplitudes);
            cleanIndices = ~isnan(cleanFeatures(:,1));
            
            if sum(cleanIndices) < 3
                clusteredSpindles = [];
                return;
            end
            
            % Determine optimal k (3-5 clusters as in paper)
            optimalK = min(5, max(3, floor(size(cleanFeatures, 1) / 10)));
            optimalK = min(optimalK, size(cleanFeatures, 1));
            
            if optimalK < 2
                clusteredSpindles = allSpindles(cleanIndices, :);
                return;
            end
            
            % Perform k-means clustering
            try
                [clusterIdx, centroids] = kmeans(cleanFeatures(cleanIndices, :), optimalK, ...
                    'Distance', 'sqeuclidean', 'Replicates', 3, 'MaxIter', 100);
                
                % Select clusters with spindle-like characteristics
                selectedClusters = obj.selectSpindleClusters(centroids, clusterIdx, ...
                    amplitudes(cleanIndices), frequencies(cleanIndices), durations(cleanIndices));
                
                % Extract spindles from selected clusters
                clusteredSpindles = allSpindles(cleanIndices, :);
                clusteredSpindles = clusteredSpindles(selectedClusters, :);
                
            catch ME
                fprintf('K-means clustering failed: %s. Using all non-coincident spindles.\n', ME.message);
                clusteredSpindles = allSpindles(cleanIndices, :);
            end
        end

        function cleanFeatures = removeAmplitudeOutliers(obj, features, amplitudes)
            % Remove amplitude outliers (10-60 µV range as in paper)
            cleanFeatures = features;
            validAmplitude = (amplitudes >= 10) & (amplitudes <= 60);
            cleanFeatures(~validAmplitude, :) = NaN;
        end

        function selectedClusters = selectSpindleClusters(obj, centroids, clusterIdx, amplitudes, frequencies, durations)
            % Select clusters that contain spindle-like events
            
            nClusters = size(centroids, 1);
            clusterScores = zeros(nClusters, 1);
            
            for i = 1:nClusters
                clusterAmplitudes = amplitudes(clusterIdx == i);
                clusterFrequencies = frequencies(clusterIdx == i);
                clusterDurations = durations(clusterIdx == i);
                
                % Score based on spindle characteristics
                ampScore = mean(clusterAmplitudes >= 15 & clusterAmplitudes <= 50);
                freqScore = mean(clusterFrequencies >= 11 & clusterFrequencies <= 16);
                durScore = mean(clusterDurations >= 0.5 & clusterDurations <= 3.0);
                
                clusterScores(i) = (ampScore + freqScore + durScore) / 3;
            end
            
            % Select clusters with score above threshold
            selectedClusters = clusterScores > 0.6;
            
            % Create mask for selected spindles
            selectedClusters = ismember(clusterIdx, find(selectedClusters));
        end

        function uniqueSpindles = removeDuplicateSpindles(obj, spindles)
            % Remove duplicate spindles based on timing and channel
            
            if isempty(spindles) || size(spindles, 1) == 1
                uniqueSpindles = spindles;
                return;
            end
            
            % Sort by channel and start time
            [~, sortIdx] = sortrows(spindles, [7, 1]); % Channel, start time
            sortedSpindles = spindles(sortIdx, :);
            
            uniqueSpindles = [];
            lastSpindle = [];
            
            for i = 1:size(sortedSpindles, 1)
                currentSpindle = sortedSpindles(i, :);
                
                if isempty(lastSpindle)
                    uniqueSpindles = currentSpindle;
                    lastSpindle = currentSpindle;
                    continue;
                end
                
                % Check if this is a duplicate (same channel and overlapping time)
                sameChannel = currentSpindle(7) == lastSpindle(7);
                timeGap = currentSpindle(1) - lastSpindle(2);
                
                if sameChannel && timeGap < 0.5 % Less than 0.5s gap
                    % Merge spindles
                    mergedSpindle = zeros(1, 7);
                    mergedSpindle(1) = min(lastSpindle(1), currentSpindle(1));
                    mergedSpindle(2) = max(lastSpindle(2), currentSpindle(2));
                    mergedSpindle(3) = mean([lastSpindle(3), currentSpindle(3)]);
                    mergedSpindle(4) = max(lastSpindle(4), currentSpindle(4));
                    mergedSpindle(5) = mergedSpindle(2) - mergedSpindle(1);
                    mergedSpindle(6) = mean([lastSpindle(6), currentSpindle(6)]);
                    mergedSpindle(7) = currentSpindle(7);
                    
                    % Replace last spindle with merged one
                    uniqueSpindles(end, :) = mergedSpindle;
                    lastSpindle = mergedSpindle;
                else
                    % Add as new spindle
                    uniqueSpindles(end+1, :) = currentSpindle;
                    lastSpindle = currentSpindle;
                end
            end
        end

        function waveletSpindles = detectWaveletSpindlesSPT(obj, channels, sleepOnly)
            % Detect spindles using Morlet wavelet method
            waveletSpindles = [];
            
            for ch = 1:length(channels)
                channelName = channels{ch};
                chIdx = find(strcmp(obj.channelLabels, channelName));
                if isempty(chIdx), continue; end
                
                % Use SPT data
                x = obj.sptData{chIdx};
                if isempty(x) || length(x) < obj.fs(chIdx) * 10
                    continue;
                end
                
                % Apply sleep restriction if needed
                if sleepOnly
                    x = obj.applySleepRestriction(x, chIdx);
                end
                
                if isempty(x) || length(x) < obj.fs(chIdx) * 10
                    continue;
                end
                
                % Detect spindles using wavelet method
                spindles = obj.detectSpindlesWavelet(x, channelName, chIdx);
                if ~isempty(spindles)
                    waveletSpindles = [waveletSpindles; spindles];
                end
            end
        end

        function rmsSpindles = detectRMSSpindlesSPT(obj, channels, sleepOnly)
            % Detect spindles using RMS method
            rmsSpindles = [];
            
            for ch = 1:length(channels)
                channelName = channels{ch};
                chIdx = find(strcmp(obj.channelLabels, channelName));
                if isempty(chIdx), continue; end

                x = obj.sptData{chIdx};
                spindles = obj.detectSpindlesSingleChannelSPT(x, channelName, 13.5, chIdx, sleepOnly);
                if ~isempty(spindles)
                    rmsSpindles = [rmsSpindles; spindles];
                end
            end
        end

        function SO_events = detectSlowOscillationsSPT(obj)
            % Detect slow oscillations using RMS method - NREM sleep only within SPT
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

                % Use SPT data instead of full data
                x = obj.sptData{chIdx};
                if isempty(x), continue; end

                % Use channel-specific sampling rate
                if length(obj.fs) >= chIdx
                    fs = obj.fs(chIdx);
                else
                    fs = obj.fs(1); % Fallback to first channel's rate
                end

                % Apply NREM sleep mask (stages 2, 3, 4) within SPT
                if ~isempty(obj.numericHypnogram)
                    sptHypnogram = obj.getSPTHypnogram();
                    samplesPerEpoch = 30 * fs;
                    nremMask = false(1, length(x));

                    for epoch = 1:min(length(sptHypnogram), ceil(length(x)/samplesPerEpoch))
                        stageNum = sptHypnogram(epoch);
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

        function events = detectSpindlesSingleChannelSPT(obj, x, channelName, center_freq, chIdx, sleepOnly)
            % RMS method spindle detection for single channel

            % Use channel-specific sampling rate
            if length(obj.fs) >= chIdx
                fs = obj.fs(chIdx);
            else
                fs = obj.fs(1);
            end

            % Clean data first
            x = x(isfinite(x));
            if isempty(x) || length(x) < fs * 10
                events = [];
                return;
            end

            % Apply sleep restriction
            if sleepOnly && ~isempty(obj.numericHypnogram)
                sptHypnogram = obj.getSPTHypnogram();
                samplesPerEpoch = 30 * fs;
                nremMask = false(1, length(x));

                for epoch = 1:min(length(sptHypnogram), ceil(length(x)/samplesPerEpoch))
                    stageNum = sptHypnogram(epoch);
                    if stageNum == 2 || stageNum == 3 || stageNum == 4
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

            % RMS with optimized window
            win_samples = round(obj.detectionParams.rmsWin * fs);
            if win_samples > length(xf)
                events = [];
                return;
            end

            rms_env = sqrt(conv(xf.^2, ones(win_samples,1)/win_samples, 'same'));

            % Smooth RMS
            rms_smooth = conv(rms_env, ones(win_samples,1)/win_samples, 'same');

            % Remove any remaining NaN/Inf values
            rms_smooth = rms_smooth(isfinite(rms_smooth));
            if isempty(rms_smooth)
                events = [];
                return;
            end

            % Optimized threshold
            threshold = mean(rms_smooth) + obj.detectionParams.threshold * std(rms_smooth);

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
                if dur < obj.detectionParams.minDuration || dur > obj.detectionParams.maxDuration
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

        function spindles = detectSpindlesWavelet(obj, x, channelName, chIdx)
            % Core wavelet spindle detection algorithm
            
            % Get sampling rate properly
            if length(obj.fs) >= chIdx
                fs = obj.fs(chIdx);
            else
                fs = obj.fs(1);
            end
            
            % Clean data
            x = x(isfinite(x));
            if isempty(x) || length(x) < fs * 10
                spindles = [];
                return;
            end
            
            % Remove mean and ensure row vector
            x = x - mean(x);
            if size(x, 1) > size(x, 2)
                x = x';
            end
            
            % Initialize output
            spindles = [];
            
            try
                % Complex Morlet Wavelet Transformation
                waveletSignal = obj.complexMorletWavelet(x, fs, ...
                    obj.waveletParams.centerFreq, obj.waveletParams.nCycles);
                
                % Smooth wavelet coefficients
                smoothSamples = round(0.1 * fs);
                waveletSignal = movmean(abs(waveletSignal), smoothSamples);
                
                % Calculate baseline and thresholds
                baseline = mean(waveletSignal);
                highThreshold = obj.waveletParams.highThresholdFactor * baseline;
                
                % Find spindle cores (high threshold crossings)
                aboveHigh = waveletSignal > highThreshold;
                spindleCores = obj.findIntervals(aboveHigh, fs, ...
                    obj.waveletParams.minDuration, obj.waveletParams.maxDuration);
                
                % Calculate spindle characteristics for each detected spindle
                for i = 1:size(spindleCores, 1)
                    startSample = spindleCores(i, 1);
                    endSample = spindleCores(i, 2);
                    
                    % Extract spindle segment
                    spindleSegment = x(startSample:endSample);
                    
                    % Calculate spindle characteristics
                    characteristics = obj.calculateSpindleCharacteristics(...
                        spindleSegment, fs, startSample, endSample);
                    
                    % Only keep if it meets quality criteria
                    if characteristics.qualityScore >= obj.waveletParams.minQualityScore
                        spindles(end+1, :) = [...
                            startSample/fs, ...          % Start time
                            endSample/fs, ...            % End time
                            characteristics.peakTime, ... % Peak time
                            characteristics.amplitude, ... % Amplitude
                            characteristics.duration, ... % Duration
                            characteristics.frequency, ... % Frequency
                            chIdx];                      % Channel index
                    end
                end
                
            catch ME
                fprintf('Error in wavelet detection for channel %s: %s\n', channelName, ME.message);
                spindles = [];
            end
        end

        function waveletSignal = complexMorletWavelet(obj, x, fs, centerFreq, nCycles)
            % Complex Morlet wavelet transformation
            
            % Create wavelet in time domain
            waveletLength = round(nCycles * fs / centerFreq);
            t = linspace(-nCycles/2, nCycles/2, waveletLength);
            
            % Standard deviation and bandwidth parameter
            sigma = nCycles / (2 * pi * centerFreq);
            FB = 2 * sigma^2;
            
            % Complex Morlet wavelet
            wavelet = (FB * pi)^(-0.5) * exp(2 * pi * 1i * centerFreq * t) .* exp(-t.^2 / FB);
            wavelet = wavelet / max(abs(wavelet)); % Normalize
            
            % Convolve signal with wavelet
            waveletSignal = conv(x, wavelet, 'same');
        end
        
        function intervals = findIntervals(obj, binarySignal, fs, minDur, maxDur)
            % Find intervals in binary signal that meet duration criteria
            
            % Find threshold crossings
            binarySignal = [false, binarySignal, false];
            d = diff(binarySignal);
            starts = find(d == 1);
            ends = find(d == -1) - 1;
            
            intervals = [];
            for i = 1:length(starts)
                dur = (ends(i) - starts(i)) / fs;
                if dur >= minDur && dur <= maxDur
                    intervals(end+1, :) = [starts(i), ends(i), dur];
                end
            end
        end

        function characteristics = calculateSpindleCharacteristics(obj, spindleSegment, fs, startSample, endSample)
            % Calculate comprehensive spindle characteristics
            
            characteristics = struct();
            
            % Basic timing
            characteristics.duration = (endSample - startSample) / fs;
            [~, peakIdx] = max(abs(spindleSegment));
            characteristics.peakTime = (startSample + peakIdx - 1) / fs;
            
            % Band-pass filter for spindle analysis
            bpFilter = designfilt('bandpassiir', ...
                'FilterOrder', 4, ...
                'HalfPowerFrequency1', 11, ...
                'HalfPowerFrequency2', 16, ...
                'SampleRate', fs);
            filteredSpindle = filtfilt(bpFilter, spindleSegment);
            
            % Amplitude (peak-to-peak)
            characteristics.amplitude = max(filteredSpindle) - min(filteredSpindle);
            
            % Frequency characteristics
            [freq, ~] = obj.calculateSpindleFrequency(filteredSpindle, fs);
            characteristics.frequency = freq;
            
            % Oscillation count
            characteristics.oscillations = obj.countOscillations(filteredSpindle);
            
            % Quality score
            characteristics.qualityScore = obj.calculateQualityScore(characteristics);
        end
        
        function [peakFreq, powerSpectrum] = calculateSpindleFrequency(obj, signal, fs)
            % Calculate spindle peak frequency using FFT
            nfft = 2^nextpow2(length(signal));
            fftResult = fft(signal, nfft);
            powerSpectrum = abs(fftResult(1:nfft/2+1)).^2;
            frequencies = linspace(0, fs/2, nfft/2+1);
            
            % Focus on spindle frequency range
            spindleRange = frequencies >= 11 & frequencies <= 16;
            [~, maxIdx] = max(powerSpectrum(spindleRange));
            freqIdx = find(spindleRange, 1) + maxIdx - 1;
            peakFreq = frequencies(freqIdx);
        end
        
        function oscillationCount = countOscillations(~, filteredSignal)
            % Count number of oscillations in spindle
            [peaks, ~] = findpeaks(filteredSignal, 'MinPeakHeight', std(filteredSignal)*0.3);
            oscillationCount = length(peaks);
        end
        
        function qualityScore = calculateQualityScore(obj, characteristics)
            % Calculate composite quality score (0-1)
            % Duration score (optimal 0.5-3.0 seconds)
            durScore = max(0, 1 - abs(characteristics.duration - 1.5) / 2.5);
            
            % Oscillation score (optimal 4-8 oscillations)
            oscScore = min(1, characteristics.oscillations / 8);
            
            % Frequency score (should be in spindle range)
            freqScore = (characteristics.frequency >= 11 && characteristics.frequency <= 16);
            
            % Amplitude score
            ampScore = min(1, characteristics.amplitude / 100);
            
            % Composite score (weighted average)
            weights = [0.3, 0.3, 0.2, 0.2];
            qualityScore = dot([durScore, oscScore, freqScore, ampScore], weights);
        end

        function setOptimizedParams(obj, p)
            % Set optimized detection parameters based on Chen et al. 2023
            dp = struct();
            dp.freqBand = [11 16];
            dp.rmsWin = 0.25; % 0.25s window as in paper
            dp.threshold = 0.95; % 0.95 times mean as in paper
            dp.minDuration = 0.5;
            dp.maxDuration = 3.0;
            dp.minInterval = 0.3;
            if isfield(p,'freqBand'), dp.freqBand = p.freqBand; end
            if isfield(p,'rmsWin'), dp.rmsWin = p.rmsWin; end
            if isfield(p,'threshold'), dp.threshold = p.threshold; end
            if isfield(p,'minDuration'), dp.minDuration = p.minDuration; end
            if isfield(p,'maxDuration'), dp.maxDuration = p.maxDuration; end
            if isfield(p,'minInterval'), dp.minInterval = p.minInterval; end
            obj.detectionParams = dp;
        end

        function setOptimizedWaveletParams(obj)
            % Set optimized wavelet detection parameters
            obj.waveletParams = struct();
            obj.waveletParams.centerFreq = 13.5;      % FC in Hz
            obj.waveletParams.nCycles = 7;            % Number of wavelet cycles
            obj.waveletParams.highThresholdFactor = 4.5; % Upper threshold multiplier
            obj.waveletParams.minDuration = 0.5;      % Minimum duration (s)
            obj.waveletParams.maxDuration = 3.0;      % Maximum duration (s)
            obj.waveletParams.minQualityScore = 0.3;  % Minimum quality score
        end

        function performMethodComparison(obj)
            % Store fusion metrics
            fprintf('Calculating fusion detection metrics...\n');
            
            metrics = struct();
            metrics.total_spindles = size(obj.spindleEvents, 1);
            metrics.fast_spindles = size(obj.fastSpindleEvents, 1);
            metrics.slow_spindles = size(obj.slowSpindleEvents, 1);
            metrics.total_SO = size(obj.SO_events, 1);
            
            % Density calculations
            totalNREMTime = obj.calculateNREMTime();
            if totalNREMTime > 0
                metrics.spindle_density = metrics.total_spindles / totalNREMTime;
                metrics.fast_density = metrics.fast_spindles / totalNREMTime;
                metrics.slow_density = metrics.slow_spindles / totalNREMTime;
                metrics.SO_density = metrics.total_SO / totalNREMTime;
            else
                metrics.spindle_density = 0;
                metrics.fast_density = 0;
                metrics.slow_density = 0;
                metrics.SO_density = 0;
            end
            
            % Frequency characteristics
            if metrics.total_spindles > 0
                metrics.mean_frequency = mean(obj.spindleEvents(:,6));
                metrics.std_frequency = std(obj.spindleEvents(:,6));
                metrics.mean_duration = mean(obj.spindleEvents(:,5));
                metrics.std_duration = std(obj.spindleEvents(:,5));
                metrics.mean_amplitude = mean(obj.spindleEvents(:,4));
                metrics.std_amplitude = std(obj.spindleEvents(:,4));
            else
                metrics.mean_frequency = 0;
                metrics.std_frequency = 0;
                metrics.mean_duration = 0;
                metrics.std_duration = 0;
                metrics.mean_amplitude = 0;
                metrics.std_amplitude = 0;
            end
            
            obj.fusionMetrics = metrics;
            
            fprintf('Fusion Detection Metrics:\n');
            fprintf('  Total Spindles: %d (Fast:%d, Slow:%d)\n', metrics.total_spindles, metrics.fast_spindles, metrics.slow_spindles);
            fprintf('  Total SO: %d\n', metrics.total_SO);
            fprintf('  Spindle Density: %.2f/min (Fast:%.2f, Slow:%.2f)\n', metrics.spindle_density, metrics.fast_density, metrics.slow_density);
            fprintf('  SO Density: %.2f/min\n', metrics.SO_density);
            fprintf('  Mean Frequency: %.2f Hz\n', metrics.mean_frequency);
            fprintf('  Mean Duration: %.2f s\n', metrics.mean_duration);
        end

        function calculateMethodComparison(obj, waveletSpindles, rmsSpindles)
            % Calculate separate statistics for RMS and wavelet methods
            fprintf('Calculating method comparison statistics...\n');
            
            obj.methodComparison = struct();
            
            % Wavelet statistics
            if ~isempty(waveletSpindles)
                obj.methodComparison.wavelet_total = size(waveletSpindles, 1);
                obj.methodComparison.wavelet_mean_freq = mean(waveletSpindles(:,6));
                obj.methodComparison.wavelet_mean_dur = mean(waveletSpindles(:,5));
                obj.methodComparison.wavelet_mean_amp = mean(waveletSpindles(:,4));
            else
                obj.methodComparison.wavelet_total = 0;
                obj.methodComparison.wavelet_mean_freq = 0;
                obj.methodComparison.wavelet_mean_dur = 0;
                obj.methodComparison.wavelet_mean_amp = 0;
            end
            
            % RMS statistics
            if ~isempty(rmsSpindles)
                obj.methodComparison.rms_total = size(rmsSpindles, 1);
                obj.methodComparison.rms_mean_freq = mean(rmsSpindles(:,6));
                obj.methodComparison.rms_mean_dur = mean(rmsSpindles(:,5));
                obj.methodComparison.rms_mean_amp = mean(rmsSpindles(:,4));
            else
                obj.methodComparison.rms_total = 0;
                obj.methodComparison.rms_mean_freq = 0;
                obj.methodComparison.rms_mean_dur = 0;
                obj.methodComparison.rms_mean_amp = 0;
            end
            
            % Fusion statistics - Calculate directly from spindleEvents
            if ~isempty(obj.spindleEvents)
                obj.methodComparison.fusion_total = size(obj.spindleEvents, 1);
                obj.methodComparison.fusion_mean_freq = mean(obj.spindleEvents(:,6));
                obj.methodComparison.fusion_mean_dur = mean(obj.spindleEvents(:,5));
                obj.methodComparison.fusion_mean_amp = mean(obj.spindleEvents(:,4));
            else
                obj.methodComparison.fusion_total = 0;
                obj.methodComparison.fusion_mean_freq = 0;
                obj.methodComparison.fusion_mean_dur = 0;
                obj.methodComparison.fusion_mean_amp = 0;
            end
            
            fprintf('Method Comparison:\n');
            fprintf('  Wavelet: %d spindles\n', obj.methodComparison.wavelet_total);
            fprintf('  RMS: %d spindles\n', obj.methodComparison.rms_total);
            fprintf('  Fusion: %d spindles\n', obj.methodComparison.fusion_total);
        end

        function performEnhancedAnalysis(obj)
            % Perform cycle analysis and channel statistics on SPT data
            fprintf('Performing enhanced analysis (cycles and channel stats) on SPT...\n');
            
            % Detect sleep cycles within SPT
            obj.detectSleepCycles();
            
            % Calculate cycle statistics with spindle type information
            obj.calculateCycleStatistics();
        end

        function detectSleepCycles(obj)
            % Detect sleep cycles from hypnogram using sleep_cycles.m function
            if isempty(obj.numericHypnogram)
                fprintf('No hypnogram available for sleep cycle detection\n');
                obj.sleepCycles = [];
                return;
            end

            fprintf('Detecting sleep cycles using sleep_cycles.m...\n');

            try
                % Create NREM-only hypnogram for cycle detection
                nrem_hypnogram = obj.numericHypnogram;

                % Set wake and REM to 0, keep NREM stages as is
                nrem_hypnogram(nrem_hypnogram == 0 | nrem_hypnogram == 1 | nrem_hypnogram == 5) = 0;

                % Use sleep_cycles function
                detected_cycles = sleep_cycles(nrem_hypnogram, 'Visible', false);

                % Ensure detected_cycles matches hypnogram length
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

            catch ME
                fprintf('Sleep cycle detection failed: %s\n', ME.message);
                fprintf('Using simple cycle detection method\n');
                obj.simpleSleepCycleDetection();
            end
        end

        function simpleSleepCycleDetection(obj)
            % Simple fallback sleep cycle detection
            sptHypnogram = obj.getSPTHypnogram();
            
            cycles = zeros(size(sptHypnogram));
            current_cycle = 0;
            in_nrem = false;
            rem_count = 0;
            
            for i = 1:length(sptHypnogram)
                stage = sptHypnogram(i);
                
                if (stage == 2 || stage == 3 || stage == 4) && ~in_nrem
                    % Start of NREM period - new cycle
                    current_cycle = current_cycle + 1;
                    in_nrem = true;
                    rem_count = 0;
                elseif stage == 5 % REM sleep
                    rem_count = rem_count + 1;
                    if rem_count >= 2 % At least 2 REM epochs to count as REM period
                        in_nrem = false;
                    end
                elseif (stage == 0 || stage == 1) && in_nrem
                    % Wake or N1 - potential cycle boundary
                    in_nrem = false;
                end
                
                if current_cycle > 0
                    cycles(i) = current_cycle;
                end
            end
            
            % Map back to full hypnogram indices
            fullCycles = zeros(size(obj.numericHypnogram));
            fullCycles(obj.sptStartEpoch:obj.sptEndEpoch) = cycles;
            obj.sleepCycles = fullCycles;

            nCycles = length(unique(cycles(cycles > 0)));
            fprintf('Simple cycle detection: %d sleep cycles\n', nCycles);
        end

        function calculateCycleStatistics(obj)
            % Calculate comprehensive cycle statistics with spindle type information
            if isempty(obj.sleepCycles) || isempty(obj.spindleEvents)
                obj.cycleStats = struct();
                return;
            end

            fprintf('Calculating enhanced cycle statistics...\n');

            uniqueCycles = unique(obj.sleepCycles(obj.sleepCycles > 0));
            stats = struct();

            for i = 1:length(uniqueCycles)
                cycleNum = uniqueCycles(i);
                cycleName = ['cycle_' num2str(cycleNum)];
                
                % Find epochs in this cycle
                cycleEpochs = find(obj.sleepCycles == cycleNum);
                if isempty(cycleEpochs), continue; end
                
                % Calculate cycle duration
                cycleDuration = length(cycleEpochs) * 0.5; % minutes
                
                % Count spindles and SOs in this cycle with type information
                cycleStats = obj.countEventsInCycle(cycleEpochs);
                
                % Store cycle statistics
                stats.(cycleName) = struct();
                stats.(cycleName).cycleNumber = cycleNum;
                stats.(cycleName).startEpoch = min(cycleEpochs);
                stats.(cycleName).endEpoch = max(cycleEpochs);
                stats.(cycleName).duration = cycleDuration;
                stats.(cycleName).total_spindles = cycleStats.total_spindles;
                stats.(cycleName).fast_spindles = cycleStats.fast_spindles;
                stats.(cycleName).slow_spindles = cycleStats.slow_spindles;
                stats.(cycleName).SO_count = cycleStats.SO_count;
                stats.(cycleName).spindle_density = cycleStats.total_spindles / max(cycleDuration, 0.1);
                stats.(cycleName).fast_density = cycleStats.fast_spindles / max(cycleDuration, 0.1);
                stats.(cycleName).slow_density = cycleStats.slow_spindles / max(cycleDuration, 0.1);
                stats.(cycleName).SO_density = cycleStats.SO_count / max(cycleDuration, 0.1);
                stats.(cycleName).channels = cycleStats.channels;
            end

            obj.cycleStats = stats;
        end

        function cycleStats = countEventsInCycle(obj, cycleEpochs)
            % Count events in specific sleep cycle with type and channel information
            cycleStats = struct();
            cycleStats.total_spindles = 0;
            cycleStats.fast_spindles = 0;
            cycleStats.slow_spindles = 0;
            cycleStats.SO_count = 0;
            cycleStats.channels = struct();
            
            % Count spindles in this cycle
            if ~isempty(obj.spindleEvents)
                for i = 1:size(obj.spindleEvents, 1)
                    epochNumber = ceil(obj.spindleEvents(i,3) / 30);
                    if ismember(epochNumber, cycleEpochs)
                        cycleStats.total_spindles = cycleStats.total_spindles + 1;
                        
                        % Check spindle type
                        freq = obj.spindleEvents(i,6);
                        if freq >= 13 && freq <= 16
                            cycleStats.fast_spindles = cycleStats.fast_spindles + 1;
                        elseif freq >= 11 && freq < 13
                            cycleStats.slow_spindles = cycleStats.slow_spindles + 1;
                        end
                        
                        % Count by channel
                        chIdx = obj.spindleEvents(i,7);
                        if chIdx <= length(obj.channelLabels)
                            chName = obj.channelLabels{chIdx};
                            fieldName = ['channel_' num2str(chIdx)];
                            
                            if ~isfield(cycleStats.channels, fieldName)
                                cycleStats.channels.(fieldName) = struct();
                                cycleStats.channels.(fieldName).name = chName;
                                cycleStats.channels.(fieldName).total_spindles = 0;
                                cycleStats.channels.(fieldName).fast_spindles = 0;
                                cycleStats.channels.(fieldName).slow_spindles = 0;
                            end
                            
                            cycleStats.channels.(fieldName).total_spindles = ...
                                cycleStats.channels.(fieldName).total_spindles + 1;
                            
                            if freq >= 13 && freq <= 16
                                cycleStats.channels.(fieldName).fast_spindles = ...
                                    cycleStats.channels.(fieldName).fast_spindles + 1;
                            elseif freq >= 11 && freq < 13
                                cycleStats.channels.(fieldName).slow_spindles = ...
                                    cycleStats.channels.(fieldName).slow_spindles + 1;
                            end
                        end
                    end
                end
            end
            
            % Count SOs in this cycle
            if ~isempty(obj.SO_events)
                for i = 1:size(obj.SO_events, 1)
                    epochNumber = ceil(obj.SO_events(i,1) / 30);
                    if ismember(epochNumber, cycleEpochs)
                        cycleStats.SO_count = cycleStats.SO_count + 1;
                    end
                end
            end
        end

        function x = applySleepRestriction(obj, x, chIdx)
            % Apply NREM sleep restriction to data (stages 2, 3, 4 only)
            
            if isempty(obj.numericHypnogram)
                return;
            end
            
            fs = obj.fs(chIdx);
            if length(obj.fs) >= chIdx
                fs = obj.fs(chIdx);
            else
                fs = obj.fs(1);
            end
            
            % Get SPT hypnogram
            sptHypnogram = obj.getSPTHypnogram();
            if isempty(sptHypnogram)
                return;
            end
            
            samplesPerEpoch = 30 * fs;
            nremMask = false(1, length(x));
            
            for epoch = 1:min(length(sptHypnogram), ceil(length(x)/samplesPerEpoch))
                stageNum = sptHypnogram(epoch);
                if stageNum == 2 || stageNum == 3 || stageNum == 4
                    startSample = (epoch-1) * samplesPerEpoch + 1;
                    endSample = min(epoch * samplesPerEpoch, length(x));
                    nremMask(startSample:endSample) = true;
                end
            end
            
            % Apply mask
            x = x(nremMask);
        end

        function totalNREMTime = calculateNREMTime(obj)
            % Calculate NREM sleep time (N2 + N3/SWS) within SPT only
            if isempty(obj.numericHypnogram)
                totalNREMTime = obj.sptDuration / 60;
                return;
            end

            sptHypnogram = obj.getSPTHypnogram();
            nremEpochs = sum(sptHypnogram == 2 | sptHypnogram == 3 | sptHypnogram == 4);
            totalNREMTime = nremEpochs * 30 / 60;
        end

        function sptHypnogram = getSPTHypnogram(obj)
            % Get hypnogram subset for SPT only
            if isempty(obj.numericHypnogram)
                sptHypnogram = [];
                return;
            end
            
            if obj.sptStartEpoch <= length(obj.numericHypnogram) && obj.sptEndEpoch <= length(obj.numericHypnogram)
                sptHypnogram = obj.numericHypnogram(obj.sptStartEpoch:obj.sptEndEpoch);
            else
                sptHypnogram = obj.numericHypnogram;
            end
        end

        function identifySleepPeriodTime(obj)
            % Identify Sleep Period Time (SPT) - from first to last sleep epoch
            if isempty(obj.numericHypnogram)
                fprintf('No hypnogram available. Using entire recording as SPT.\n');
                obj.sptStartEpoch = 1;
                obj.sptEndEpoch = length(obj.data{1}) / (30 * obj.fs(1));
                obj.sptStartSample = 1;
                obj.sptEndSample = length(obj.data{1});
                obj.sptDuration = length(obj.data{1}) / obj.fs(1);
                return;
            end

            % Find first and last sleep epochs (stages 1-5)
            sleepEpochs = find(obj.numericHypnogram >= 1 & obj.numericHypnogram <= 5);
            
            if isempty(sleepEpochs)
                warning('No sleep epochs found in hypnogram. Using entire recording.');
                obj.sptStartEpoch = 1;
                obj.sptEndEpoch = length(obj.numericHypnogram);
                obj.sptStartSample = 1;
                obj.sptEndSample = length(obj.data{1});
                obj.sptDuration = length(obj.data{1}) / obj.fs(1);
                return;
            end

            obj.sptStartEpoch = min(sleepEpochs);
            obj.sptEndEpoch = max(sleepEpochs);
            
            % Convert epochs to samples
            samplesPerEpoch = 30 * obj.fs(1);
            obj.sptStartSample = (obj.sptStartEpoch - 1) * samplesPerEpoch + 1;
            obj.sptEndSample = min(obj.sptEndEpoch * samplesPerEpoch, length(obj.data{1}));
            obj.sptDuration = (obj.sptEndSample - obj.sptStartSample + 1) / obj.fs(1);

            fprintf('Sleep Period Time identified:\n');
            fprintf('  Epochs: %d to %d (%d epochs)\n', obj.sptStartEpoch, obj.sptEndEpoch, obj.sptEndEpoch - obj.sptStartEpoch + 1);
            fprintf('  Samples: %d to %d (%d samples)\n', obj.sptStartSample, obj.sptEndSample, obj.sptEndSample - obj.sptStartSample + 1);
            fprintf('  Duration: %.1f minutes (reduced from %.1f minutes)\n', ...
                obj.sptDuration/60, length(obj.data{1})/obj.fs(1)/60);
            
            originalDuration = length(obj.data{1}) / obj.fs(1) / 60;
            sptDuration = obj.sptDuration / 60;
            reduction = ((originalDuration - sptDuration) / originalDuration) * 100;
            fprintf('  Compute reduction: %.1f%%\n', reduction);
        end

        function performDataCleaningSPT(obj, channels)
            % Perform targeted data cleaning ONLY on SPT data
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

            fprintf('Targeted cleaning for %d EEG channels (SPT only): %s\n', ...
                length(eegChannelIndices), strjoin(eegChannelNames, ', '));

            % Extract SPT data for cleaning
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

            % Prepare SPT data for cleaning
            dataToClean = cell(1, length(cleaningChannels));
            labelsToClean = cell(1, length(cleaningChannels));
            for i = 1:length(cleaningChannels)
                fullData = obj.data{cleaningChannels(i)};
                if obj.sptStartSample <= length(fullData) && obj.sptEndSample <= length(fullData)
                    sptData = fullData(obj.sptStartSample:obj.sptEndSample);
                else
                    sptData = fullData;
                end
                dataToClean{i} = sptData;
                labelsToClean{i} = cleaningLabels{i};
            end

            cleaning_fs = obj.fs(1);
            sptHypnogram = obj.getSPTHypnogram();
            
            [cleanData, artifactInfo] = obj.artifactDetector.fullDataCleaning(...
                dataToClean, labelsToClean, cleaning_fs, sptHypnogram);

            % Store cleaned SPT data
            obj.sptData = cell(1, length(obj.data));
            for i = 1:length(obj.data)
                if i <= length(eegChannelIndices)
                    obj.sptData{i} = cleanData{i};
                else
                    fullData = obj.data{i};
                    if obj.sptStartSample <= length(fullData) && obj.sptEndSample <= length(fullData)
                        obj.sptData{i} = fullData(obj.sptStartSample:obj.sptEndSample);
                    else
                        obj.sptData{i} = fullData;
                    end
                end
            end

            obj.cleaningSummary = obj.artifactDetector.getCleaningSummary();
        end

        function loadHypnogram(obj)
            % Load hypnogram from XML file
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
            % Setup channel mapping and load data
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

            % Get sampling rates for ALL channels
            obj.fs = obj.getSamplingRates();

            fprintf('Mapped %d channels\n', length(obj.channelLabels));

            % Show EEG channel sampling rates
            eeg_patterns = {'F3', 'F4', 'C3', 'C4', 'O1', 'O2', 'Fz', 'Cz', 'Pz', 'Oz'};
            eeg_channels = {};

            for i = 1:length(obj.channelLabels)
                channelName = obj.channelLabels{i};
                is_eeg = false;
                for pattern = eeg_patterns
                    if startsWith(channelName, [pattern{1} '-']) || ...
                       startsWith(channelName, pattern{1}) || ...
                       contains(channelName, 'EEG')
                        is_eeg = true;
                        break;
                    end
                end
                if is_eeg
                    eeg_channels{end+1} = channelName;
                end
            end

            fprintf('EEG Channel Sampling Rates:\n');
            for i = 1:length(eeg_channels)
                chIdx = find(strcmp(obj.channelLabels, eeg_channels{i}));
                if ~isempty(chIdx) && chIdx <= length(obj.fs)
                    fprintf('  %s: %d Hz\n', eeg_channels{i}, obj.fs(chIdx));
                end
            end

            if ~isempty(eeg_channels)
                eeg_indices = [];
                for i = 1:length(eeg_channels)
                    chIdx = find(strcmp(obj.channelLabels, eeg_channels{i}));
                    if ~isempty(chIdx)
                        eeg_indices(end+1) = chIdx;
                    end
                end
                unique_eeg_rates = unique(obj.fs(eeg_indices));
                fprintf('Unique EEG sampling rates: %s Hz\n', mat2str(unique_eeg_rates));
            end
        end

        function fs_array = getSamplingRates(obj)
            % Get sampling rates for all channels
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
                fprintf('Error reading sampling rates, using default: 256 Hz for all %d channels\n', length(obj.channelLabels));
            end
        end

        function data = loadEDFData(obj, channelIndices)
            % Load EDF data for specified channels
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

        % NEW RESULT TABLE METHODS WITH ALL IMPROVEMENTS
        function [fusionTable, methodTable, channelStatsTable, stageStatsTable, cycleStatsTable, temporalRelationsTable, qualityTable] = buildConsolidatedResultTables(obj)
            % Build all consolidated result tables with improvements

               fprintf('Building comprehensive consolidated result tables...\n');

    % 1. FUSION DETECTION METRICS TABLE
    fusionTable = obj.buildFusionMetricsTable();

    % 2. METHOD COMPARISON TABLE
    methodTable = obj.buildMethodComparisonTable();

    % 3. CHANNEL STATISTICS TABLE (overall channel summaries)
    channelStatsTable = obj.buildChannelStatsTable();

    % 4. STAGE STATISTICS TABLE (NOW: by channel)
    stageStatsTable = obj.buildStageStatsTable();

    % 5. CYCLE STATISTICS TABLE (NOW: by channel and stage)
    cycleStatsTable = obj.buildCycleStatsTable();

    % 6. TEMPORAL RELATIONSHIPS TABLE
    temporalRelationsTable = obj.buildTemporalRelationshipsTable();

    % 7. DATA QUALITY TABLE
    qualityTable = obj.buildQualityTable();

end

        function fusionTable = buildFusionMetricsTable(obj)
            % Build fusion detection metrics table with spindle type information
            fprintf('Building fusion metrics table...\n');

            metrics = obj.fusionMetrics;
            
            data = {
                'Total_Spindles', metrics.total_spindles;
                'Fast_Spindles', metrics.fast_spindles;
                'Slow_Spindles', metrics.slow_spindles;
                'Total_SO', metrics.total_SO;
                'Spindle_Density_perMin', metrics.spindle_density;
                'Fast_Spindle_Density_perMin', metrics.fast_density;
                'Slow_Spindle_Density_perMin', metrics.slow_density;
                'SO_Density_perMin', metrics.SO_density;
                'Mean_Frequency_Hz', metrics.mean_frequency;
                'Std_Frequency_Hz', metrics.std_frequency;
                'Mean_Duration_s', metrics.mean_duration;
                'Std_Duration_s', metrics.std_duration;
                'Mean_Amplitude', metrics.mean_amplitude;
                'Std_Amplitude', metrics.std_amplitude;
                'SPT_Duration_min', obj.sptDuration / 60;
                'NREM_Time_min', obj.calculateNREMTime();
                };

            fusionTable = cell2table(data, 'VariableNames', {'Metric', 'Value'});
        end
        
        function methodTable = buildMethodComparisonTable(obj)
            % Build method comparison table
            fprintf('Building method comparison table...\n');

            if isempty(obj.methodComparison)
                methodTable = table();
                return;
            end

            methods = {'Wavelet'; 'RMS'; 'Fusion'};
            total_spindles = [
                obj.methodComparison.wavelet_total;
                obj.methodComparison.rms_total; 
                obj.methodComparison.fusion_total
            ];
            mean_frequency = [
                obj.methodComparison.wavelet_mean_freq;
                obj.methodComparison.rms_mean_freq;
                obj.methodComparison.fusion_mean_freq
            ];
            mean_duration = [
                obj.methodComparison.wavelet_mean_dur;
                obj.methodComparison.rms_mean_dur;
                obj.methodComparison.fusion_mean_dur
            ];
            mean_amplitude = [
                obj.methodComparison.wavelet_mean_amp;
                obj.methodComparison.rms_mean_amp;
                obj.methodComparison.fusion_mean_amp
            ];

            methodTable = table(methods, total_spindles, mean_frequency, mean_duration, mean_amplitude, ...
                'VariableNames', {'Method', 'Total_Spindles', 'Mean_Frequency_Hz', 'Mean_Duration_s', 'Mean_Amplitude'});
        end

        function channelStatsTable = buildChannelStatsTable(obj)
    % Build regional channel statistics table with stage breakdown
    fprintf('Building regional channel statistics table with stage breakdown...\n');

    if isempty(obj.channelStats)
        channelStatsTable = table();
        return;
    end

    stats = obj.channelStats;
    fieldNames = fieldnames(stats)';
    stages = {'N1', 'N2', 'N3', 'REM'};
    
    data = {};
    for i = 1:length(fieldNames)
        fieldName = fieldNames{i};
        if isfield(stats, fieldName)
            regionData = stats.(fieldName);
            
            % Main region summary row
            data{end+1, 1} = regionData.region_name;
            data{end, 2} = 'SUMMARY';
            data{end, 3} = strjoin(regionData.channels, ', ');
            data{end, 4} = regionData.total_spindles;
            data{end, 5} = regionData.fast_spindles;
            data{end, 6} = regionData.slow_spindles;
            data{end, 7} = regionData.SO_count;
            data{end, 8} = regionData.mean_frequency;
            data{end, 9} = regionData.mean_duration;
            data{end, 10} = regionData.mean_amplitude;
            data{end, 11} = regionData.fast_mean_freq;
            data{end, 12} = regionData.slow_mean_freq;
            data{end, 13} = regionData.spindle_density;
            data{end, 14} = regionData.fast_density;
            data{end, 15} = regionData.slow_density;
            data{end, 16} = regionData.SO_density;
            
            % Stage-specific rows
            for stage_idx = 1:length(stages)
                stage = stages{stage_idx};
                data{end+1, 1} = regionData.region_name;
                data{end, 2} = stage;
                data{end, 3} = strjoin(regionData.channels, ', ');
                data{end, 4} = regionData.(['total_' stage]);
                data{end, 5} = regionData.(['fast_' stage]);
                data{end, 6} = regionData.(['slow_' stage]);
                data{end, 7} = regionData.(['SO_' stage]);
                data{end, 8} = NaN; % Frequency not calculated per stage
                data{end, 9} = NaN; % Duration not calculated per stage
                data{end, 10} = NaN; % Amplitude not calculated per stage
                data{end, 11} = NaN; % Fast freq not calculated per stage
                data{end, 12} = NaN; % Slow freq not calculated per stage
                data{end, 13} = regionData.([stage '_spindle_density']);
                data{end, 14} = regionData.([stage '_fast_density']);
                data{end, 15} = regionData.([stage '_slow_density']);
                data{end, 16} = regionData.([stage '_SO_density']);
            end
        end
    end

    if isempty(data)
        channelStatsTable = table();
    else
        channelStatsTable = cell2table(data, 'VariableNames', {
            'Region', 'Breakdown', 'Channels', 'Total_Spindles', 'Fast_Spindles', 'Slow_Spindles', 'SO_Count', ...
            'Mean_Frequency_Hz', 'Mean_Duration_s', 'Mean_Amplitude', ...
            'Fast_Mean_Freq_Hz', 'Slow_Mean_Freq_Hz', ...
            'Spindle_Density_perMin', 'Fast_Density_perMin', 'Slow_Density_perMin', 'SO_Density_perMin'
            });
    end
end

        function stageStatsTable = buildStageStatsTable(obj)
    % Build enhanced stage statistics table with channel breakdown AND totals
    fprintf('Building enhanced stage statistics table with totals...\n');

    % Use the pre-computed table that already includes channel breakdown + totals
    if isempty(obj.stageStatsTable) || height(obj.stageStatsTable) == 0
        % Fallback: create basic table if the enhanced one isn't available
        stages = {'N1', 'N2', 'N3', 'REM'};
        data = {};
        
        for i = 1:length(stages)
            stage = stages{i};
            stageNum = obj.getStageNumber(stage);
            
            total_spindles = obj.countSpindlesInStage(stageNum);
            fast_spindles = obj.countFastSpindlesInStage(stageNum);
            slow_spindles = obj.countSlowSpindlesInStage(stageNum);
            
            stageDurations = obj.calculateStageDurations();
            stage_duration = stageDurations.(stage);
            
            spindle_density = 0;
            if stage_duration > 0
                spindle_density = total_spindles / stage_duration;
            end
            
            data{end+1, 1} = stage;
            data{end, 2} = total_spindles;
            data{end, 3} = fast_spindles;
            data{end, 4} = slow_spindles;
            data{end, 5} = stage_duration;
            data{end, 6} = spindle_density;
        end
        
        if isempty(data)
            stageStatsTable = table();
        else
            stageStatsTable = cell2table(data, 'VariableNames', {
                'Stage', 'Total_Spindles', 'Fast_Spindles', 'Slow_Spindles', ...
                'Stage_Duration_min', 'Spindle_Density_perMin'
                });
        end
    else
        % Use the enhanced table with channel breakdown and totals
        stageStatsTable = obj.stageStatsTable;
    end
    
    fprintf('Stage statistics table: %d rows\n', height(stageStatsTable));
end

function cycleStatsTable = buildCycleStatsTable(obj)
    % Build enhanced cycle statistics table with channel-stage breakdown AND totals
    fprintf('Building enhanced cycle statistics table with totals...\n');

    % Use the pre-computed table that already includes channel-stage breakdown + totals
    if isempty(obj.cycleStatsTable) || height(obj.cycleStatsTable) == 0
        % Fallback: create basic table if the enhanced one isn't available
        if isempty(obj.cycleStats)
            cycleStatsTable = table();
            return;
        end
        
        stats = obj.cycleStats;
        fieldNames = fieldnames(stats)';
        
        data = {};
        for i = 1:length(fieldNames)
            fieldName = fieldNames{i};
            if isfield(stats, fieldName)
                cycleData = stats.(fieldName);
                data{end+1, 1} = cycleData.cycleNumber;
                data{end, 2} = cycleData.startEpoch;
                data{end, 3} = cycleData.endEpoch;
                data{end, 4} = cycleData.duration;
                data{end, 5} = cycleData.total_spindles;
                data{end, 6} = cycleData.fast_spindles;
                data{end, 7} = cycleData.slow_spindles;
                data{end, 8} = cycleData.SO_count;
                data{end, 9} = cycleData.spindle_density;
            end
        end
        
        if isempty(data)
            cycleStatsTable = table();
        else
            cycleStatsTable = cell2table(data, 'VariableNames', {
                'CycleNumber', 'StartEpoch', 'EndEpoch', 'Duration_min', ...
                'Total_Spindles', 'Fast_Spindles', 'Slow_Spindles', 'SO_Count', ...
                'Spindle_Density_perMin'
                });
        end
    else
        % Use the enhanced table with channel-stage breakdown and totals
        cycleStatsTable = obj.cycleStatsTable;
    end
    
    fprintf('Cycle statistics table: %d rows\n', height(cycleStatsTable));
end

        function temporalRelationsTable = buildTemporalRelationshipsTable(obj)
            % Build comprehensive SO-spindle temporal relationships table
            fprintf('Building temporal relationships table...\n');

            if isempty(obj.temporalRelations) || ~isfield(obj.temporalRelations, 'SO_count')
                temporalRelationsTable = table();
                return;
            end

            rel = obj.temporalRelations;
            
            data = {
                'Total_SO_Count', rel.SO_count;
                'Total_Spindle_Count', rel.spindle_count;
                'Fast_Spindle_Count', rel.fast_spindle_count;
                'Slow_Spindle_Count', rel.slow_spindle_count;
                'Mean_Time_Difference_s', rel.mean_time_diff;
                'Std_Time_Difference_s', rel.std_time_diff;
                'Median_Time_Difference_s', rel.median_time_diff;
                'Mean_Coupling_Strength', rel.mean_coupling_strength;
                'Early_Coupled_Count', rel.early_coupled_count;
                'Late_Coupled_Count', rel.late_coupled_count;
                'Tightly_Coupled_Count', rel.tightly_coupled_count;
                'Early_Coupled_Percent', rel.early_coupled_percent;
                'Late_Coupled_Percent', rel.late_coupled_percent;
                'Tightly_Coupled_Percent', rel.tightly_coupled_percent;
                'Fast_Spindle_Mean_Time_Diff_s', rel.fast_mean_time_diff;
                'Slow_Spindle_Mean_Time_Diff_s', rel.slow_mean_time_diff;
                'Fast_Spindle_Mean_Coupling', rel.fast_mean_coupling;
                'Slow_Spindle_Mean_Coupling', rel.slow_mean_coupling;
                };

            temporalRelationsTable = cell2table(data, 'VariableNames', {'Parameter', 'Value'});
        end

        function qualityTable = buildQualityTable(obj)
            % Build data quality summary table
            fprintf('Building quality table...\n');

            totalNREMTime = obj.calculateNREMTime();
            
            qualityData = {
                'Total_SPT_Time_min', obj.sptDuration / 60;
                'Total_NREM_Time_min', totalNREMTime;
                'Artifact_Free_Percent', obj.getFieldSafe(obj.cleaningSummary, 'cleanDataPercentage', 0);
                'Artifact_Percent', obj.getFieldSafe(obj.cleaningSummary, 'artifactPercentage', 0);
                'ECG_Decontamination_Applied', obj.getFieldSafe(obj.cleaningSummary, 'ecgDecontaminationApplied', false);
                'Total_Artifacts', obj.getFieldSafe(obj.cleaningSummary, 'totalArtifacts', 0);
                'Total_Spindles', size(obj.spindleEvents, 1);
                'Total_Fast_Spindles', size(obj.fastSpindleEvents, 1);
                'Total_Slow_Spindles', size(obj.slowSpindleEvents, 1);
                'Total_SO', size(obj.SO_events, 1);
                'Spindle_Density', size(obj.spindleEvents, 1) / max(totalNREMTime, 0.1);
                'Fast_Spindle_Density', size(obj.fastSpindleEvents, 1) / max(totalNREMTime, 0.1);
                'Slow_Spindle_Density', size(obj.slowSpindleEvents, 1) / max(totalNREMTime, 0.1);
                'SO_Density', size(obj.SO_events, 1) / max(totalNREMTime, 0.1);
                'Mean_Spindle_Frequency_Hz', obj.fusionMetrics.mean_frequency;
                'Mean_Spindle_Duration_s', obj.fusionMetrics.mean_duration;
                };

            qualityTable = cell2table(qualityData, 'VariableNames', {'Parameter', 'Value'});
        end

        function writeConsolidatedResultsToExcel(obj, outputFile, fusionTable, methodTable, channelStatsTable, ...
                stageStatsTable, cycleStatsTable, temporalRelationsTable, qualityTable)
            % Write all consolidated tables to Excel file

            fprintf('Writing comprehensive consolidated results to Excel...\n');

            try
                if exist(outputFile, 'file')
                    delete(outputFile);
                end

                if ~isempty(fusionTable) && height(fusionTable) > 0
                    writetable(fusionTable, outputFile, 'Sheet', 'Fusion_Metrics');
                end
      
                if ~isempty(methodTable) && height(methodTable) > 0
                    writetable(methodTable, outputFile, 'Sheet', 'Method_Comparison');
                end

                if ~isempty(channelStatsTable) && height(channelStatsTable) > 0
                    writetable(channelStatsTable, outputFile, 'Sheet', 'Channel_Statistics');
                end

                if ~isempty(stageStatsTable) && height(stageStatsTable) > 0
                    writetable(stageStatsTable, outputFile, 'Sheet', 'Stage_Statistics');
                end

                if ~isempty(cycleStatsTable) && height(cycleStatsTable) > 0
                    writetable(cycleStatsTable, outputFile, 'Sheet', 'Cycle_Statistics');
                end

                if ~isempty(temporalRelationsTable) && height(temporalRelationsTable) > 0
                    writetable(temporalRelationsTable, outputFile, 'Sheet', 'Temporal_Relationships');
                end

                if ~isempty(qualityTable) && height(qualityTable) > 0
                    writetable(qualityTable, outputFile, 'Sheet', 'Data_Quality');
                end

                fprintf('Successfully saved comprehensive results to: %s\n', outputFile);

            catch ME
                fprintf('Error writing Excel file: %s\n', ME.message);
                rethrow(ME);
            end
        end

        function saveResults(obj, outputFile)
            % Save comprehensive consolidated results
            if isempty(obj.spindleEvents)
                obj.saveEmptyResults(outputFile);
                return;
            end

            fprintf('Saving COMPREHENSIVE consolidated results...\n');
            fprintf('Analysis performed only on Sleep Period Time: %.1f minutes\n', obj.sptDuration/60);

            % Build all consolidated result tables
            [fusionTable, methodTable, channelStatsTable, stageStatsTable, cycleStatsTable, temporalRelationsTable, qualityTable] = ...
                obj.buildConsolidatedResultTables();

            % Write all sheets to Excel
            obj.writeConsolidatedResultsToExcel(outputFile, fusionTable, methodTable, channelStatsTable, ...
                stageStatsTable, cycleStatsTable, temporalRelationsTable, qualityTable);
        end

        function saveEmptyResults(obj, outputFile)
            % Save empty results when no spindles detected
            warning('No spindles to save.');

            emptyTable = table();

            writetable(emptyTable, outputFile, 'Sheet', 'Fusion_Metrics');
            writetable(emptyTable, outputFile, 'Sheet', 'Method_Comparison');
            writetable(emptyTable, outputFile, 'Sheet', 'Channel_Statistics');
            writetable(emptyTable, outputFile, 'Sheet', 'Stage_Statistics');
            writetable(emptyTable, outputFile, 'Sheet', 'Cycle_Statistics');
            writetable(emptyTable, outputFile, 'Sheet', 'Temporal_Relationships');
            writetable(emptyTable, outputFile, 'Sheet', 'Data_Quality');

            fprintf('Saved empty results to: %s\n', outputFile);
        end

        function value = getFieldSafe(~, structure, fieldName, defaultValue)
            % Safely get field value with default
            if isfield(structure, fieldName)
                value = structure.(fieldName);
            else
                value = defaultValue;
            end
        end

        % Keep all original counting methods
        function count = countSpindlesInStage(obj, stageNum)
            % Count spindles in specific sleep stage
            count = 0;
            
            if isempty(obj.spindleEvents)
                return;
            end

            for i = 1:size(obj.spindleEvents, 1)
                epochNumber = ceil(obj.spindleEvents(i,3) / 30);
                if epochNumber <= length(obj.numericHypnogram) && obj.numericHypnogram(epochNumber) == stageNum
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

        function stageNum = getStageNumber(~, stageName)
            % Convert stage name to number
            switch stageName
                case 'N1', stageNum = 1;
                case 'N2', stageNum = 2;
                case 'N3', stageNum = 3;
                case 'REM', stageNum = 5;
                otherwise, stageNum = 0;
            end
        end
    end
end