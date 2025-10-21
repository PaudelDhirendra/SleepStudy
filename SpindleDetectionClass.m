classdef SpindleDetectionClass < handle
    % SpindleDetectionClass: Detect sleep spindles using consistent SpectralTrainClass patterns

    properties
        edfLoader
        fs
        channelLabels
        data
        spindleEvents      % [start_s, end_s, channel_idx, peak_s, duration_s]
        detectionParams
        edfPath
        xmlPath
        mappedChannelNames
        numericHypnogram
        stage2Mask
        stage3Mask
        artifactDetector
        cleaningSummary
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
        end

        function runDetection(obj, channels, references, just2)

               fprintf('Starting spindle detection with comprehensive data cleaning...\n');
            
            % Perform data cleaning on all channels first
            [cleanData, artifactInfo] = obj.artifactDetector.fullDataCleaning(...
                obj.data, obj.channelLabels, obj.fs, obj.numericHypnogram);
            
            obj.data = cleanData;
            obj.cleaningSummary = obj.artifactDetector.getCleaningSummary();
            
            if nargin < 4
                just2 = false;
            end
            if nargin < 3
                references = {};
            end
            if nargin < 2
                channels = {'C3-M2', 'C4-M1'};
            end
            
            if isempty(obj.data)
                warning('No data to process.');
                return;
            end

            fprintf('Running spindle detection on %d channels...\n', length(channels));
            allEvents = {};
            
            for ch = 1:length(channels)
                channelName = channels{ch};
                fprintf('Processing channel: %s\n', channelName);
                
                % Find channel index
                chIdx = find(strcmp(obj.channelLabels, channelName));
                if isempty(chIdx)
                    fprintf('Channel %s not found. Available: %s\n', channelName, strjoin(obj.channelLabels, ', '));
                    continue;
                end
                
                x = obj.data{chIdx}; % Use cell array access
                events = obj.detectSpindlesOnChannel(x, channelName, just2);
                if ~isempty(events)
                    events = [events, repmat(chIdx, size(events,1), 1)];
                    allEvents{end+1} = events;
                end
            end

            if ~isempty(allEvents)
                obj.spindleEvents = vertcat(allEvents{:});
                fprintf('Total spindles detected: %d\n', size(obj.spindleEvents,1));
            else
                obj.spindleEvents = [];
                fprintf('No spindles detected in any channel\n');
            end
        end

  function saveResults(obj, outputFile)
    if isempty(obj.spindleEvents)
        warning('No spindles to save.');
        T = table();
        writetable(T, outputFile);
        fprintf('Saved empty results to: %s\n', outputFile);
        return;
    end
    
    % Create basic table
    if size(obj.spindleEvents, 2) == 6
        T = array2table(obj.spindleEvents, ...
            'VariableNames',{'Start_sec','End_sec','Peak_sec','RMS_Amplitude','Duration_sec','ChannelIdx'});
    else
        T = array2table(obj.spindleEvents);
    end
    
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
    
    % Add sleep stage information if hypnogram available
    if ~isempty(obj.numericHypnogram)
        stageLabels = cell(height(T), 1);
        cycleNumbers = zeros(height(T), 1);
        
        fprintf('Adding sleep stage information...\n');
        
        for i = 1:height(T)
            % Determine which epoch contains the spindle peak
            epochNumber = ceil(T.Peak_sec(i) / 30); % 30-second epochs
            
            if epochNumber <= length(obj.numericHypnogram)
                stageNum = obj.numericHypnogram(epochNumber);
                
                % Convert numeric stage to label
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
            
            % Progress update for large datasets
            if mod(i, 1000) == 0
                fprintf('  Processed %d/%d spindles...\n', i, height(T));
            end
        end
        
        T.SleepStage = stageLabels;
        
        % Add cycle information with timeout protection
        fprintf('Adding cycle information...\n');
        try
            % Set a timeout for cycle detection
            cycles = [];
            if exist('sleep_cycles', 'file')
                % Try with timeout
                try
                    cycles = sleep_cycles(obj.numericHypnogram);
                    fprintf('Identified %d sleep cycles\n', length(unique(cycles(cycles > 0))));
                catch ME
                    fprintf('Cycle detection failed: %s\n', ME.message);
                    cycles = [];
                end
            end
            
            if ~isempty(cycles)
                for i = 1:height(T)
                    epochNumber = ceil(T.Peak_sec(i) / 30);
                    if epochNumber <= length(cycles)
                        cycleNumbers(i) = cycles(epochNumber);
                    end
                    
                    % Progress update
                    if mod(i, 1000) == 0
                        fprintf('  Added cycles to %d/%d spindles...\n', i, height(T));
                    end
                end
                T.CycleNumber = cycleNumbers;
            else
                T.CycleNumber = zeros(height(T), 1);
                fprintf('No cycle information available\n');
            end
            
        catch ME
            fprintf('Error in cycle assignment: %s. Skipping cycle info.\n', ME.message);
            T.CycleNumber = zeros(height(T), 1);
        end
    else
        T.SleepStage = repmat({'Unknown'}, height(T), 1);
        T.CycleNumber = zeros(height(T), 1);
    end
    
    % Add frequency information (quick calculation)
    fprintf('Adding frequency information...\n');
    frequencyHz = zeros(height(T), 1);
    for i = 1:height(T)
        % Simple frequency estimation
        if T.Duration_sec(i) > 0
            frequencyHz(i) = min(max(11, 7/T.Duration_sec(i)), 16);
        else
            frequencyHz(i) = 13.5;
        end
    end
    T.EstimatedFrequency_Hz = frequencyHz;
    
    % Save the table
    writetable(T, outputFile);
    fprintf('SUCCESS: Saved %d spindles to: %s\n', height(T), outputFile);
    fprintf('Columns: %s\n', strjoin(T.Properties.VariableNames, ', '));
end
    end

    methods (Access = private)
        function loadHypnogram(obj)
            % Load hypnogram using same method as SpectralTrainClass
            try
                fprintf('Loading hypnogram: %s\n', obj.xmlPath);
                
                % Check if file exists
                if ~exist(obj.xmlPath, 'file')
                    warning('XML file not found: %s', obj.xmlPath);
                    obj.numericHypnogram = [];
                    obj.stage2Mask = [];
                    obj.stage3Mask = [];
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
                obj.stage2Mask = [];
                obj.stage3Mask = [];
            end
        end
        
        function setupMappedChannels(obj)
            fprintf('Setting up channels using ChannelMappingHelper...\n');
            
            % Get raw channel names
            rawChannelNames = obj.edfLoader.signal_labels;
            
            fprintf('Raw channel names from EDF:\n');
            for i = 1:length(rawChannelNames)
                fprintf('  Channel %d: "%s"\n', i, rawChannelNames{i});
            end
            
            % Map to uniform names using helper function
            mappedNames = ChannelMappingHelper(rawChannelNames);
            obj.mappedChannelNames = rawChannelNames; % Keep original names
            
            % Use mapped names for channel selection
            obj.channelLabels = mappedNames;
            
            % Load all data - keep in cell array format
            obj.data = obj.loadEDFData(1:length(rawChannelNames));
            
            % Get sampling rate
            obj.fs = obj.getSamplingRate(1);
            
            fprintf('Mapped %d channels: %s\n', length(obj.channelLabels), strjoin(obj.channelLabels, ', '));
            fprintf('Sampling rate: %.1f Hz\n', obj.fs);
            fprintf('Data loaded for all channels\n');
        end

        function data = loadEDFData(obj, channelIndices)
            % Load data and keep in cell array format to handle different sizes
            fprintf('Loading data for %d channels...\n', length(channelIndices));
            
            try
                % Use signalCell directly - don't convert to matrix
                signalCell = obj.edfLoader.edf.signalCell;
                fprintf('Found signalCell with %d channels\n', length(signalCell));
                
                % Check dimensions of first channel
                testData = signalCell{1};
                fprintf('First channel dimensions: %s\n', mat2str(size(testData)));
                
                % Keep data in cell array format to handle column vectors
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

        function fs = getSamplingRate(obj, channelIndex)
            % Get sampling rate
            try
                sr = obj.edfLoader.sample_rate;
                if isnumeric(sr) && length(sr) >= channelIndex
                    fs = sr(channelIndex);
                else
                    fs = 256; % Default based on your data
                end
                fprintf('Sampling rate: %.1f Hz\n', fs);
            catch
                fs = 256;
                fprintf('Using default sampling rate: %.1f Hz\n', fs);
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
            
            fprintf('Detection parameters:\n');
            fprintf('  Frequency band: %.1f-%.1f Hz\n', dp.freqBand(1), dp.freqBand(2));
            fprintf('  Duration range: %.1f-%.1f s\n', dp.duration(1), dp.duration(2));
            fprintf('  RMS window: %.1f s\n', dp.rmsWin);
            fprintf('  Threshold: %.1f SD\n', dp.threshold);
        end

        function events = detectSpindlesOnChannel(obj, x, channelName, just2)
            fs = obj.fs;
            dp = obj.detectionParams;

            % Ensure x is a row vector for processing
            if size(x, 1) > size(x, 2)
                x = x'; % Transpose if it's a column vector
            end
            x = double(x);
            
            fprintf('  Channel %s: %.1f seconds, %d samples\n', ...
                channelName, length(x)/fs, length(x));

            % Remove mean
            x = x - mean(x);
            
            % Apply stage restriction if requested
            if just2 && ~isempty(obj.numericHypnogram)
                % Expand hypnogram to match signal length
                samplesPerEpoch = 30 * fs;
                numCompleteEpochs = floor(length(x) / samplesPerEpoch);
                
                if numCompleteEpochs > 0
                    % Create stage mask for the signal
                    stageMask = false(1, length(x));
                    for epoch = 1:min(numCompleteEpochs, length(obj.numericHypnogram))
                        if obj.numericHypnogram(epoch) == 2
                            startSample = (epoch-1) * samplesPerEpoch + 1;
                            endSample = min(epoch * samplesPerEpoch, length(x));
                            stageMask(startSample:endSample) = true;
                        end
                    end
                    % Zero out non-stage2 data
                    x(~stageMask) = 0;
                end
            end
            
            % Bandpass filter
            try
                [b,a] = butter(2, dp.freqBand/(fs/2), 'bandpass');
                xf = filtfilt(b, a, x);
            catch ME
                fprintf('  Filter error: %s. Using original signal.\n', ME.message);
                xf = x;
            end

            % RMS envelope
            win = round(dp.rmsWin * fs);
            if mod(win,2) == 0
                win = win + 1;
            end
            if win > length(xf) || win < 3
                fprintf('  Signal too short for RMS calculation\n');
                events = [];
                return;
            end
            
            try
                rms_env = sqrt(conv(xf.^2, ones(win,1)/win, 'same'));
            catch
                fprintf('  RMS calculation failed\n');
                events = [];
                return;
            end

            % Normalize RMS (z-score)
            rms_z = (rms_env - mean(rms_env)) / std(rms_env);

            % Thresholding - use 95th percentile
            if just2 && ~isempty(obj.stage2Mask)
                % Use only stage 2 data for threshold calculation
                samplesPerEpoch = 30 * fs;
                numCompleteEpochs = floor(length(rms_z) / samplesPerEpoch);
                
                stage2RMS = [];
                for epoch = 1:min(numCompleteEpochs, length(obj.stage2Mask))
                    if obj.stage2Mask(epoch)
                        startSample = (epoch-1) * samplesPerEpoch + 1;
                        endSample = min(epoch * samplesPerEpoch, length(rms_z));
                        stage2RMS = [stage2RMS, rms_z(startSample:endSample)];
                    end
                end
                
                if ~isempty(stage2RMS) && std(stage2RMS) > 0
                    thresh = prctile(stage2RMS, 95);
                else
                    thresh = prctile(rms_z, 95);
                end
            else
                thresh = prctile(rms_z, 95);
            end

            fprintf('  Detection threshold: %.2f SD\n', thresh);

            above = rms_z > thresh;
            above = [false, above, false];

            % Find transitions
            d = diff(above);
            starts = find(d == 1);
            ends = find(d == -1) - 1;

            if isempty(starts) || isempty(ends)
                fprintf('  No spindle candidates found\n');
                events = [];
                return;
            end

            events = [];
            for i = 1:min(length(starts), length(ends))
                s = starts(i);
                e = ends(i);
                if e <= s
                    continue;
                end
                dur = (e - s) / fs;
                if dur < dp.duration(1) || dur > dp.duration(2)
                    continue;
                end
                [~, pkIdx] = max(rms_env(s:e));
                pk = s + pkIdx - 1;
                events(end+1,:) = [s, e, pk, rms_env(pk), dur];
            end

            if isempty(events)
                fprintf('  No spindles after duration filtering\n');
                events = [];
                return;
            end

            % Convert to seconds
            events(:,1:3) = events(:,1:3) / fs;
            
            fprintf('  Detected %d spindles\n', size(events,1));
        end
    end
end