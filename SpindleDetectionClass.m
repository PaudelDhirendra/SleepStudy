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
            % Constructor
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
            obj.performDataCleaning(channels);

            % Set default parameters - Mölle method only detects in NREM sleep
            if nargin < 4
                just2 = true; % Default to NREM sleep only (N2 + SWS)
            end
            if nargin < 3
                references = {};
            end

            % Run Mölle detection method
            obj.runMolleDetection(just2);
        end

        function saveResults(obj, outputFile)
            % Save comprehensive results using Mölle method
            if isempty(obj.spindleEvents)
                obj.saveEmptyResults(outputFile);
                return;
            end

            fprintf('Saving comprehensive Mölle et al. (2011) method results...\n');

            % Build all result tables
            [spindleTable, SO_table, globalTable, channelStats, stageStats, cycleStats, qualityTable] = ...
                obj.buildResultTables();

            % Write all sheets to Excel
            obj.writeResultsToExcel(outputFile, spindleTable, SO_table, globalTable, ...
                channelStats, stageStats, cycleStats, qualityTable);
        end

        function totalSleepTime = calculateTotalSleepTime(obj)
            % Calculate total sleep time from hypnogram
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
            % Count spindles in specific sleep stage
            count = 0;
            for i = 1:size(obj.spindleEvents, 1)
                epochNumber = ceil(obj.spindleEvents(i,3) / 30);
                if epochNumber <= length(obj.numericHypnogram) && obj.numericHypnogram(epochNumber) == stageNum
                    count = count + 1;
                end
            end
        end

        function count = countSpindlesInStageByType(obj, stageNum, spindleType)
            % Count spindles in specific sleep stage by type
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
            fprintf('Sampling rates: %s Hz\n', mat2str(obj.fs));
        end

        function fs_array = getSamplingRates(obj)
            % Get sampling rates for all channels
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

        function setDefaultParams(obj, p)
            % Set default detection parameters
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

        function performDataCleaning(obj, channels)
            % Perform targeted data cleaning for EEG channels
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

            % Use first channel's sampling rate for cleaning
            cleaning_fs = obj.fs(1);
            [cleanData, artifactInfo] = obj.artifactDetector.fullDataCleaning(...
                dataToClean, labelsToClean, cleaning_fs, obj.numericHypnogram);

            for i = 1:length(eegChannelIndices)
                obj.data{eegChannelIndices(i)} = cleanData{i};
            end

            obj.cleaningSummary = obj.artifactDetector.getCleaningSummary();
        end

        function runMolleDetection(obj, just2)
            % Run complete Mölle detection pipeline
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

                % Use channel-specific sampling rate
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

            % Use channel-specific sampling rate
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

        function saveEmptyResults(obj, outputFile)
            % Save empty results when no spindles detected
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
        end

        function [spindleTable, SO_table, globalTable, channelStats, stageStats, cycleStats, qualityTable] = buildResultTables(obj)
            % Build all result tables for saving

            %% 1. INDIVIDUAL SPINDLE EVENTS
            fprintf('Building individual spindle table...\n');
            spindleTable = obj.buildSpindleTable();

            %% 2. SLOW OSCILLATION EVENTS
            SO_table = obj.buildSOTable();

            %% 3. COMPREHENSIVE SUMMARY STATISTICS
            fprintf('Building summary statistics...\n');
            [globalTable, channelStats, stageStats, cycleStats] = obj.buildSummaryTables(spindleTable);

            %% 4. DATA QUALITY
            qualityTable = obj.buildQualityTable();
        end

        function spindleTable = buildSpindleTable(obj)
            % Build individual spindle events table
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
            T = obj.addSleepStageInfo(T);

            % Add cycle information
            T = obj.addCycleInfo(T);

            spindleTable = T;
        end

        function T = addSleepStageInfo(obj, T)
            % Add sleep stage information to table
            if ~isempty(obj.numericHypnogram)
                fprintf('Adding sleep stage information...\n');
                nSpindles = height(T);
                stageLabels = cell(nSpindles, 1);

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
                T.SleepStage = repmat({'Unknown'}, height(T), 1);
            end
        end

        function T = addCycleInfo(obj, T)
            % Add sleep cycle information to table
            if ~isempty(obj.numericHypnogram)
                fprintf('Adding cycle information (NREM-based)...\n');
                nSpindles = height(T);
                cycleNumbers = zeros(nSpindles, 1);

                try
                    if exist('sleep_cycles', 'file')
                        % Create NREM-only hypnogram for cycle detection
                        nrem_hypnogram = obj.numericHypnogram;
                        nrem_hypnogram(nrem_hypnogram == 0 | nrem_hypnogram == 1 | nrem_hypnogram == 5) = 0;

                        [~, cycle_starts, cycle_ends] = sleep_cycles(nrem_hypnogram, 30);

                        for i = 1:nSpindles
                            epochNumber = ceil(T.Peak_sec(i) / 30);
                            for cycle = 1:length(cycle_starts)
                                if epochNumber >= cycle_starts(cycle) && epochNumber <= cycle_ends(cycle)
                                    cycleNumbers(i) = cycle;
                                    break;
                                end
                            end
                        end
                    end
                catch ME
                    fprintf('Cycle detection failed: %s\n', ME.message);
                end

                T.CycleNumber = cycleNumbers;
            else
                T.CycleNumber = zeros(height(T), 1);
            end
        end

        function SO_table = buildSOTable(obj)
            % Build slow oscillation events table
            if isempty(obj.SO_events)
                SO_table = table();
                return;
            end

            T = array2table(obj.SO_events, ...
                'VariableNames', {'Peak_sec','Duration_sec','Amplitude_uV','ChannelIdx'});

            % Add channel names
            channelNames = cell(height(T), 1);
            for i = 1:height(T)
                if T.ChannelIdx(i) <= length(obj.channelLabels)
                    channelNames{i} = obj.channelLabels{T.ChannelIdx(i)};
                else
                    channelNames{i} = 'Unknown';
                end
            end
            T.ChannelName = channelNames;

            % Add sleep stage information
            if ~isempty(obj.numericHypnogram)
                stageLabels = cell(height(T), 1);
                for i = 1:height(T)
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
                T.SleepStage = repmat({'Unknown'}, height(T), 1);
            end

            SO_table = T;
        end

        function [globalTable, channelStats, stageStats, cycleStats] = buildSummaryTables(obj, spindleTable)
            % Build comprehensive summary tables

            %% GLOBAL STATISTICS
            globalTable = obj.buildGlobalStatistics(spindleTable);

            %% CHANNEL STATISTICS
            channelStats = obj.buildChannelStatistics(spindleTable);

            %% STAGE STATISTICS
            stageStats = obj.buildStageStatistics(spindleTable);

            %% CYCLE STATISTICS
            cycleStats = obj.buildCycleStatistics(spindleTable);
        end

        function globalTable = buildGlobalStatistics(obj, spindleTable)
            % Build global summary statistics
            fprintf('Building global statistics...\n');

            nSpindles = size(obj.spindleEvents, 1);
            nSlow = size(obj.slow_spindles, 1);
            nFast = size(obj.fast_spindles, 1);
            nSO = size(obj.SO_events, 1);

            % Calculate densities
            TST = obj.calculateTotalSleepTime();
            NREM_time = obj.calculateNREMTime();

            if TST > 0
                spindleDensity = nSpindles / TST;
                slowSpindleDensity = nSlow / TST;
                fastSpindleDensity = nFast / TST;
            else
                spindleDensity = 0;
                slowSpindleDensity = 0;
                fastSpindleDensity = 0;
            end

            if NREM_time > 0
                nremSpindleDensity = nSpindles / NREM_time;
                nremSlowSpindleDensity = nSlow / NREM_time;
                nremFastSpindleDensity = nFast / NREM_time;
                SODensity = nSO / NREM_time;
            else
                nremSpindleDensity = 0;
                nremSlowSpindleDensity = 0;
                nremFastSpindleDensity = 0;
                SODensity = 0;
            end

            % Calculate spindle characteristics
            if nSpindles > 0
                meanDuration = mean(spindleTable.Duration_sec);
                meanFrequency = mean(spindleTable.Frequency_Hz);
                meanAmplitude = mean(spindleTable.RMS_Amplitude);
                stdDuration = std(spindleTable.Duration_sec);
                stdFrequency = std(spindleTable.Frequency_Hz);
                stdAmplitude = std(spindleTable.RMS_Amplitude);
            else
                meanDuration = 0; meanFrequency = 0; meanAmplitude = 0;
                stdDuration = 0; stdFrequency = 0; stdAmplitude = 0;
            end

            % Build table
            globalTable = table(...
                nSpindles, nSlow, nFast, nSO, ...
                spindleDensity, slowSpindleDensity, fastSpindleDensity, ...
                nremSpindleDensity, nremSlowSpindleDensity, nremFastSpindleDensity, SODensity, ...
                meanDuration, stdDuration, meanFrequency, stdFrequency, meanAmplitude, stdAmplitude, ...
                TST, NREM_time, ...
                'VariableNames', {...
                'TotalSpindles', 'SlowSpindles', 'FastSpindles', 'SlowOscillations', ...
                'SpindleDensity_perMin', 'SlowSpindleDensity_perMin', 'FastSpindleDensity_perMin', ...
                'NREM_SpindleDensity_perMin', 'NREM_SlowSpindleDensity_perMin', 'NREM_FastSpindleDensity_perMin', 'SO_Density_perMin', ...
                'MeanDuration_sec', 'StdDuration_sec', 'MeanFrequency_Hz', 'StdFrequency_Hz', 'MeanAmplitude', 'StdAmplitude', ...
                'TotalSleepTime_min', 'NREM_Time_min'});
        end

        function channelStats = buildChannelStatistics(obj, spindleTable)
            % Build channel-wise statistics
            fprintf('Building channel statistics...\n');

            if isempty(spindleTable)
                channelStats = table();
                return;
            end

            uniqueChannels = unique(spindleTable.ChannelName);
            nChannels = length(uniqueChannels);

            channelNames = cell(nChannels, 1);
            spindleCounts = zeros(nChannels, 1);
            slowCounts = zeros(nChannels, 1);
            fastCounts = zeros(nChannels, 1);
            meanDurations = zeros(nChannels, 1);
            meanFrequencies = zeros(nChannels, 1);
            meanAmplitudes = zeros(nChannels, 1);

            for i = 1:nChannels
                channelName = uniqueChannels{i};
                channelNames{i} = channelName;

                mask = strcmp(spindleTable.ChannelName, channelName);
                channelSpindles = spindleTable(mask, :);

                spindleCounts(i) = height(channelSpindles);
                slowCounts(i) = sum(strcmp(channelSpindles.SpindleType, 'Slow'));
                fastCounts(i) = sum(strcmp(channelSpindles.SpindleType, 'Fast'));

                if spindleCounts(i) > 0
                    meanDurations(i) = mean(channelSpindles.Duration_sec);
                    meanFrequencies(i) = mean(channelSpindles.Frequency_Hz);
                    meanAmplitudes(i) = mean(channelSpindles.RMS_Amplitude);
                end
            end

            channelStats = table(...
                channelNames, spindleCounts, slowCounts, fastCounts, ...
                meanDurations, meanFrequencies, meanAmplitudes, ...
                'VariableNames', {...
                'ChannelName', 'SpindleCount', 'SlowSpindleCount', 'FastSpindleCount', ...
                'MeanDuration_sec', 'MeanFrequency_Hz', 'MeanAmplitude'});
        end

        function stageStats = buildStageStatistics(obj, spindleTable)
            % Build sleep stage statistics
            fprintf('Building stage statistics...\n');

            if isempty(spindleTable) || ~ismember('SleepStage', spindleTable.Properties.VariableNames)
                stageStats = table();
                return;
            end

            stages = {'N1', 'N2', 'N3', 'REM'};
            nStages = length(stages);

            stageNames = cell(nStages, 1);
            spindleCounts = zeros(nStages, 1);
            slowCounts = zeros(nStages, 1);
            fastCounts = zeros(nStages, 1);
            stageTimes = zeros(nStages, 1);

            for i = 1:nStages
                stage = stages{i};
                stageNames{i} = stage;

                mask = strcmp(spindleTable.SleepStage, stage);
                stageSpindles = spindleTable(mask, :);

                spindleCounts(i) = height(stageSpindles);
                slowCounts(i) = sum(strcmp(stageSpindles.SpindleType, 'Slow'));
                fastCounts(i) = sum(strcmp(stageSpindles.SpindleType, 'Fast'));

                % Calculate stage time
                switch stage
                    case 'N1', stageNum = 1;
                    case 'N2', stageNum = 2;
                    case 'N3', stageNum = 3;
                    case 'REM', stageNum = 5;
                    otherwise, stageNum = 0;
                end

                if ~isempty(obj.numericHypnogram)
                    stageEpochs = sum(obj.numericHypnogram == stageNum);
                    stageTimes(i) = stageEpochs * 30 / 60; % minutes
                else
                    stageTimes(i) = 0;
                end
            end

            % Calculate densities
            densities = zeros(nStages, 1);
            slowDensities = zeros(nStages, 1);
            fastDensities = zeros(nStages, 1);

            for i = 1:nStages
                if stageTimes(i) > 0
                    densities(i) = spindleCounts(i) / stageTimes(i);
                    slowDensities(i) = slowCounts(i) / stageTimes(i);
                    fastDensities(i) = fastCounts(i) / stageTimes(i);
                end
            end

            stageStats = table(...
                stageNames, spindleCounts, slowCounts, fastCounts, ...
                stageTimes, densities, slowDensities, fastDensities, ...
                'VariableNames', {...
                'Stage', 'SpindleCount', 'SlowSpindleCount', 'FastSpindleCount', ...
                'StageTime_min', 'SpindleDensity_perMin', 'SlowSpindleDensity_perMin', 'FastSpindleDensity_perMin'});
        end

        function cycleStats = buildCycleStatistics(obj, spindleTable)
            % Build sleep cycle statistics
            fprintf('Building cycle statistics...\n');

            if isempty(spindleTable) || ~ismember('CycleNumber', spindleTable.Properties.VariableNames)
                cycleStats = table();
                return;
            end

            validCycles = spindleTable.CycleNumber(spindleTable.CycleNumber > 0);
            if isempty(validCycles)
                cycleStats = table();
                return;
            end

            uniqueCycles = unique(validCycles);
            nCycles = length(uniqueCycles);

            cycleNumbers = zeros(nCycles, 1);
            spindleCounts = zeros(nCycles, 1);
            slowCounts = zeros(nCycles, 1);
            fastCounts = zeros(nCycles, 1);
            meanDurations = zeros(nCycles, 1);
            meanFrequencies = zeros(nCycles, 1);

            for i = 1:nCycles
                cycle = uniqueCycles(i);
                cycleNumbers(i) = cycle;

                mask = spindleTable.CycleNumber == cycle;
                cycleSpindles = spindleTable(mask, :);

                spindleCounts(i) = height(cycleSpindles);
                slowCounts(i) = sum(strcmp(cycleSpindles.SpindleType, 'Slow'));
                fastCounts(i) = sum(strcmp(cycleSpindles.SpindleType, 'Fast'));

                if spindleCounts(i) > 0
                    meanDurations(i) = mean(cycleSpindles.Duration_sec);
                    meanFrequencies(i) = mean(cycleSpindles.Frequency_Hz);
                end
            end

            cycleStats = table(...
                cycleNumbers, spindleCounts, slowCounts, fastCounts, ...
                meanDurations, meanFrequencies, ...
                'VariableNames', {...
                'CycleNumber', 'SpindleCount', 'SlowSpindleCount', 'FastSpindleCount', ...
                'MeanDuration_sec', 'MeanFrequency_Hz'});
        end

        function qualityTable = buildQualityTable(obj)
            % Build data quality summary table
            fprintf('Building quality table...\n');

            if isempty(obj.cleaningSummary)
                qualityTable = table();
                return;
            end

            try
                % Extract cleaning summary information
                totalChannels = length(obj.cleaningSummary.channelStats);
                totalSamples = 0;
                totalArtifactSamples = 0;

                channelNames = cell(totalChannels, 1);
                totalSamplesPerChannel = zeros(totalChannels, 1);
                artifactSamplesPerChannel = zeros(totalChannels, 1);
                artifactPercentage = zeros(totalChannels, 1);

                for i = 1:totalChannels
                    stats = obj.cleaningSummary.channelStats(i);
                    channelNames{i} = stats.channelName;
                    totalSamplesPerChannel(i) = stats.totalSamples;
                    artifactSamplesPerChannel(i) = stats.artifactSamples;
                    artifactPercentage(i) = stats.artifactPercentage;

                    totalSamples = totalSamples + stats.totalSamples;
                    totalArtifactSamples = totalArtifactSamples + stats.artifactSamples;
                end

                overallArtifactPercentage = (totalArtifactSamples / totalSamples) * 100;

                % Create quality table
                qualityTable = table(...
                    channelNames, totalSamplesPerChannel, artifactSamplesPerChannel, artifactPercentage, ...
                    'VariableNames', {'ChannelName', 'TotalSamples', 'ArtifactSamples', 'ArtifactPercentage'});

                % Add overall summary as first row
                overallRow = table(...
                    {'OVERALL'}, totalSamples, totalArtifactSamples, overallArtifactPercentage, ...
                    'VariableNames', {'ChannelName', 'TotalSamples', 'ArtifactSamples', 'ArtifactPercentage'});

                qualityTable = [overallRow; qualityTable];

            catch ME
                fprintf('Error building quality table: %s\n', ME.message);
                qualityTable = table();
            end
        end

        function writeResultsToExcel(obj, outputFile, spindleTable, SO_table, globalTable, ...
                channelStats, stageStats, cycleStats, qualityTable)
            % Write all tables to Excel file with multiple sheets

            fprintf('Writing comprehensive results to Excel...\n');

            try
                % Delete existing file
                if exist(outputFile, 'file')
                    delete(outputFile);
                end

                % Write individual sheets
                if ~isempty(spindleTable)
                    writetable(spindleTable, outputFile, 'Sheet', 'Individual_Spindles');
                end

                if ~isempty(SO_table)
                    writetable(SO_table, outputFile, 'Sheet', 'Slow_Oscillations');
                end

                if ~isempty(globalTable)
                    writetable(globalTable, outputFile, 'Sheet', 'Global_Statistics');
                end

                if ~isempty(channelStats)
                    writetable(channelStats, outputFile, 'Sheet', 'Channel_Statistics');
                end

                if ~isempty(stageStats)
                    writetable(stageStats, outputFile, 'Sheet', 'Stage_Statistics');
                end

                if ~isempty(cycleStats)
                    writetable(cycleStats, outputFile, 'Sheet', 'Cycle_Statistics');
                end

                if ~isempty(qualityTable)
                    writetable(qualityTable, outputFile, 'Sheet', 'Data_Quality');
                end

                fprintf('Successfully saved results to: %s\n', outputFile);

            catch ME
                fprintf('Error writing Excel file: %s\n', ME.message);
                rethrow(ME);
            end
        end
    end
end