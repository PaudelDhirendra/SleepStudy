classdef ArtifactDetectionClass < handle
    properties
        % Artifact detection parameters
        artifactTH = [2.5 2.0]  % [deltaTh BetaTh]
        numMovingAvg30secEpochs = 15
        deltaBand = [0.6 4.6]
        betaBand = [20 45]
        swaBand = [0.5 5.5]
        artifactMask
        deltaArtifactMask
        betaArtifactMask
        
        % ECG decontamination parameters
        ecgName = {'ECG', 'EKG', 'ECG1', 'EKG1'}
        denoiseEcg = true
        ecgDecontaminationApplied = false
        ecgContaminationScore
        
        % General parameters
        fs
        channelLabels
    end
    
    methods
        function obj = ArtifactDetectionClass(fs, channelLabels)
            % Constructor
            if nargin >= 1
                obj.fs = fs;
            end
            if nargin >= 2
                obj.channelLabels = channelLabels;
            end
        end
        
        function setECGParameters(obj, ecgName, denoiseEcg)
            if nargin >= 2
                if ischar(ecgName)
                    obj.ecgName = {ecgName};
                else
                    obj.ecgName = ecgName;
                end
            end
            if nargin >= 3
                obj.denoiseEcg = denoiseEcg;
            end
        end
        
        function [cleanData, artifactInfo] = fullDataCleaning(obj, data, signalLabels, fs, numericHypnogram)
            % Comprehensive data cleaning pipeline: ECG decontamination + artifact detection
            % Inputs:
            %   data - cell array or matrix of EEG signals
            %   signalLabels - cell array of channel names
            %   fs - sampling rate
            %   numericHypnogram - sleep staging vector
            
            fprintf('Targeted data cleaning: %d channels (%s)\n', ...
            length(signalLabels), strjoin(signalLabels, ', '));


            fprintf('Starting comprehensive data cleaning pipeline...\n');
            
            obj.fs = fs;
            obj.channelLabels = signalLabels;
            
            % Step 1: ECG Decontamination
            if obj.denoiseEcg
                data = obj.ecgDecontamination(data, signalLabels, fs);
            else
                fprintf('ECG decontamination disabled\n');
            end
            
            % Step 2: Artifact Detection
            artifactInfo = obj.detectArtifacts(data, fs, numericHypnogram);
            
            % Step 3: Apply artifact mask
            cleanData = obj.applyArtifactMask(data, fs);
            
            fprintf('Data cleaning complete:\n');
            fprintf('  - ECG decontamination: %s\n', string(obj.ecgDecontaminationApplied));
            fprintf('  - Artifacts detected: %d epochs (%.1f%%)\n', ...
                sum(obj.artifactMask), mean(obj.artifactMask)*100);
            
            artifactInfo.ecgDecontaminationApplied = obj.ecgDecontaminationApplied;
            artifactInfo.ecgContaminationScore = obj.ecgContaminationScore;
        end
        
    function cleanData = ecgDecontamination(obj, data, signalLabels, fs)
    % ECG decontamination using same method as SpectralTrainClass
    fprintf('Performing ECG decontamination...\n');
    
    % Find ECG channel
    ecgChannel = obj.findECGChannel(signalLabels);
    if isempty(ecgChannel)
        warning('No ECG channel found for decontamination. Available channels: %s', strjoin(signalLabels, ', '));
        obj.ecgDecontaminationApplied = false;
        cleanData = data;
        return;
    end
    
    fprintf('Using ECG channel: %s (index %d)\n', signalLabels{ecgChannel}, ecgChannel);


    % === ADDED: ECG QUALITY CHECK ===
    % Extract ECG signal for quality check
    if iscell(data)
        ecgSignalForCheck = data{ecgChannel};
    else
        ecgSignalForCheck = data(ecgChannel, :);
    end
    
    % Check ECG quality before proceeding
    if ~obj.checkECGQuality(ecgSignalForCheck, fs)
        fprintf('ECG quality check failed - skipping decontamination\n');
        obj.ecgDecontaminationApplied = false;
        cleanData = data;
        return;
    end
    % === END OF QUALITY CHECK ===
    
    % Handle both cell array and matrix formats consistently
    isCellData = iscell(data);
    
    try
        if isCellData
            % Data is cell array - handle different sampling rates properly
            ecgSignal = data{ecgChannel};
            ecgLength = length(ecgSignal);
            
            fprintf('ECG signal length: %d samples\n', ecgLength);
            
            % Prepare EEG signals for decontamination
            eegSignals = {};
            eegLabels = {};
            eegIndices = [];
            
            for i = 1:length(data)
                if i == ecgChannel
                    continue; % Skip ECG channel
                end
                
                eegSignal = data{i};
                eegLength = length(eegSignal);
                
                fprintf('EEG channel %d (%s) length: %d samples\n', i, signalLabels{i}, eegLength);
                
                if eegLength == ecgLength
                    % Same length - use as is
                    eegSignals{end+1} = eegSignal;
                    eegLabels{end+1} = signalLabels{i};
                    eegIndices(end+1) = i;
                else
                    % Different lengths - need resampling
                    fprintf('  Resampling EEG channel %d from %d to %d samples\n', i, eegLength, ecgLength);
                    
                    if eegLength > ecgLength
                        % EEG has higher sampling rate - downsample
                        ratio = eegLength / ecgLength;
                        if abs(ratio - 2) < 0.1
                            % Common case: 2:1 ratio - simple decimation
                            eegResampled = decimate(eegSignal, 2);
                        else
                            % General case - use resample
                            eegResampled = resample(eegSignal, 1, round(ratio));
                        end
                    else
                        % EEG has lower sampling rate - upsample
                        ratio = ecgLength / eegLength;
                        if abs(ratio - 2) < 0.1
                            % Common case: 1:2 ratio - simple interpolation
                            eegResampled = interp(eegSignal, 2);
                        else
                            % General case - use resample
                            eegResampled = resample(eegSignal, round(ratio), 1);
                        end
                    end
                    
                    % Ensure final length matches ECG
                    if length(eegResampled) > ecgLength
                        eegResampled = eegResampled(1:ecgLength);
                    elseif length(eegResampled) < ecgLength
                        eegResampled(end+1:ecgLength) = 0;
                    end
                    
                    eegSignals{end+1} = eegResampled;
                    eegLabels{end+1} = signalLabels{i};
                    eegIndices(end+1) = i;
                end
            end
            
            if isempty(eegSignals)
                error('No valid EEG signals found for decontamination');
            end
            
            fprintf('Using %d EEG channels for ECG decontamination\n', length(eegSignals));
            
        else
            % Data is matrix - all channels should have same length
            ecgSignal = data(ecgChannel, :);
            eegSignals = cell(1, size(data, 1)-1);
            eegLabels = cell(1, size(data, 1)-1);
            
            nonEcgIdx = setdiff(1:size(data,1), ecgChannel);
            for i = 1:length(nonEcgIdx)
                eegSignals{i} = data(nonEcgIdx(i), :);
                eegLabels{i} = signalLabels{nonEcgIdx(i)};
            end
        end
        
        % Additional safety check
        if isempty(eegSignals)
            error('No EEG signals available for decontamination');
        end
        
        % Verify all signals now have consistent lengths
        refLength = length(ecgSignal);
        for i = 1:length(eegSignals)
            if length(eegSignals{i}) ~= refLength
                error('Signal length mismatch after resampling: channel %d has %d samples, expected %d', ...
                    i, length(eegSignals{i}), refLength);
            end
        end
        
        % Use the same ecgDecont function as in SpectralTrainClass
        fprintf('Calling ecgDecont function with %d EEG channels...\n', length(eegSignals));
        cleanEEG = ecgDecont(eegSignals, fs, ecgSignal, fs, eegLabels);
        
        % Validate cleaned EEG data
        if isempty(cleanEEG)
            error('ecgDecont returned empty results');
        end
        
        % Reconstruct data with cleaned EEG
        if isCellData
            % For cell array format, create new cell array with cleaned data
            cleanData = cell(1, length(data));
            
            % Put cleaned EEG channels back in their original positions
            for i = 1:length(eegIndices)
                origIdx = eegIndices(i);
                if i <= length(cleanEEG)
                    cleanData{origIdx} = cleanEEG{i};
                else
                    cleanData{origIdx} = data{origIdx}; % Fallback to original
                end
            end
            
            % Keep ECG channel as original
            cleanData{ecgChannel} = ecgSignal;
            
            % Fill any remaining channels with original data
            for i = 1:length(data)
                if isempty(cleanData{i})
                    cleanData{i} = data{i};
                end
            end
            
        else
            % Convert back to matrix format
            cleanData = zeros(size(data));
            cleanData(ecgChannel, :) = ecgSignal; % Keep original ECG
            
            % Place cleaned EEG data in their original positions
            nonEcgIdx = setdiff(1:size(data,1), ecgChannel);
            for i = 1:length(nonEcgIdx)
                if i <= length(cleanEEG) && length(cleanEEG{i}) == size(cleanData, 2)
                    cleanData(nonEcgIdx(i), :) = cleanEEG{i};
                else
                    fprintf('Warning: Cleaned EEG channel %d length mismatch. Using original data.\n', i);
                    cleanData(nonEcgIdx(i), :) = data(nonEcgIdx(i), :);
                end
            end
        end
        
        obj.ecgDecontaminationApplied = true;
        obj.estimateECGContamination(data, cleanData);
        
        fprintf('ECG decontamination completed successfully\n');
        
    catch ME
        warning('ECG decontamination failed: %s. Using original data.', ME.message);
        fprintf('Error details:\n');
        fprintf('  Data type: %s\n', class(data));
        if isCellData
            fprintf('  Number of channels: %d\n', length(data));
            if ~isempty(data)
                fprintf('  ECG channel length: %d\n', length(data{ecgChannel}));
            end
        else
            fprintf('  Data dimensions: %s\n', mat2str(size(data)));
        end
        cleanData = data;
        obj.ecgDecontaminationApplied = false;
    end
end



        function ecgChannel = findECGChannel(obj, signalLabels)
            % Find ECG channel using flexible matching
            ecgChannel = [];
            
            if isempty(signalLabels)
                return;
            end
            
            % First pass: exact matches
            for i = 1:length(signalLabels)
                if isempty(signalLabels{i})
                    continue;
                end
                
                currentLabel = upper(strtrim(signalLabels{i}));
                
                % Exact matches with common ECG patterns
                ecgPatterns = {'ECG', 'EKG', 'ECG1', 'EKG1', 'ECG2', 'EKG2', 'ELECTROCARDIO'};
                for j = 1:length(ecgPatterns)
                    if strcmp(currentLabel, upper(ecgPatterns{j})) || ...
                       contains(currentLabel, upper(ecgPatterns{j}))
                        ecgChannel = i;
                        fprintf('Found ECG channel: %s (index %d)\n', signalLabels{i}, i);
                        return;
                    end
                end
            end
            
            % Second pass: partial matches
            if isempty(ecgChannel)
                for i = 1:length(signalLabels)
                    if isempty(signalLabels{i})
                        continue;
                    end
                    
                    currentLabel = upper(strtrim(signalLabels{i}));
                    
                    % Look for ECG in various formats
                    if contains(currentLabel, 'ECG') || contains(currentLabel, 'EKG')
                        ecgChannel = i;
                        fprintf('Found potential ECG channel: %s (index %d)\n', signalLabels{i}, i);
                        return;
                    end
                end
            end
            
            % Final attempt: check if any channel name matches the configured ECG names
            if isempty(ecgChannel) && ~isempty(obj.ecgName)
                for i = 1:length(signalLabels)
                    if isempty(signalLabels{i})
                        continue;
                    end
                    
                    currentLabel = upper(strtrim(signalLabels{i}));
                    for j = 1:length(obj.ecgName)
                        if contains(currentLabel, upper(obj.ecgName{j}))
                            ecgChannel = i;
                            fprintf('Found ECG channel via config: %s (index %d)\n', signalLabels{i}, i);
                            return;
                        end
                    end
                end
            end
        end
        
        function estimateECGContamination(obj, originalData, cleanedData)
            % Estimate ECG contamination level by comparing original and cleaned data
            try
                if iscell(originalData) && iscell(cleanedData)
                    % Use first channel for estimation if available
                    if ~isempty(originalData) && ~isempty(cleanedData) && ...
                       length(originalData) > 0 && length(cleanedData) > 0
                        orig = originalData{1};
                        clean = cleanedData{1};
                        
                        % Ensure same length
                        minLen = min(length(orig), length(clean));
                        if minLen > 0
                            orig = orig(1:minLen);
                            clean = clean(1:minLen);
                        else
                            obj.ecgContaminationScore = 0;
                            return;
                        end
                    else
                        obj.ecgContaminationScore = 0;
                        return;
                    end
                elseif ~iscell(originalData) && ~iscell(cleanedData)
                    % Matrix format
                    if size(originalData, 1) > 0 && size(cleanedData, 1) > 0 && ...
                       size(originalData, 2) > 0 && size(cleanedData, 2) > 0
                        orig = originalData(1, :);
                        clean = cleanedData(1, :);
                        
                        % Ensure same length
                        minLen = min(length(orig), length(clean));
                        if minLen > 0
                            orig = orig(1:minLen);
                            clean = clean(1:minLen);
                        else
                            obj.ecgContaminationScore = 0;
                            return;
                        end
                    else
                        obj.ecgContaminationScore = 0;
                        return;
                    end
                else
                    % Mixed formats - cannot compare
                    obj.ecgContaminationScore = 0;
                    return;
                end
                
                % Calculate RMS difference (ECG artifact component)
                artifactComponent = orig - clean;
                rmsArtifact = rms(artifactComponent);
                rmsOriginal = rms(orig);
                
                if rmsOriginal > 0
                    obj.ecgContaminationScore = rmsArtifact / rmsOriginal * 100;
                else
                    obj.ecgContaminationScore = 0;
                end
                
                fprintf('ECG contamination estimate: %.1f%%\n', obj.ecgContaminationScore);
                
            catch ME
                fprintf('Could not estimate ECG contamination: %s\n', ME.message);
                obj.ecgContaminationScore = NaN;
            end
        end
        
        function artifactInfo = detectArtifacts(obj, data, fs, sleepStages)
            % Detect artifacts using spectral method (same as SpectralTrainClass)
            fprintf('Performing artifact detection...\n');
            
            % Use first channel for artifact detection
            if iscell(data)
                if isempty(data)
                    warning('No data available for artifact detection');
                    artifactInfo = struct();
                    return;
                end
                refChannel = 1;
                x = data{refChannel};
            else
                if isempty(data)
                    warning('No data available for artifact detection');
                    artifactInfo = struct();
                    return;
                end
                refChannel = 1;
                x = data(refChannel, :);
            end
            
            % Compute PSD for artifact detection
            spectralBinWidth = 4; % seconds
            noverlap = 10;
            window = hanning(spectralBinWidth * fs);
            noverlapPts = floor((noverlap*spectralBinWidth*fs-30*fs)/(noverlap-1));
            
            % Reshape into 30-second epochs
            samplesPer30sec = 30 * fs;
            numCompleteEpochs = floor(length(x) / samplesPer30sec);
            
            if numCompleteEpochs > 0
                dataReshaped = reshape(x(1:numCompleteEpochs*samplesPer30sec), ...
                    samplesPer30sec, numCompleteEpochs);
                
                % Compute PSD for each epoch
                pwelchF = @(epoch)pwelch(dataReshaped(:,epoch), window, noverlapPts, spectralBinWidth*fs, fs);
                pxxCell = arrayfun(pwelchF, 1:numCompleteEpochs, 'UniformOutput', false);
                pxx = cell2mat(pxxCell);
                
                % Frequency vector
                freq = linspace(0, fs/2, size(pxx, 1));
                
                % Find frequency indices for bands
                deltaStart = find(obj.deltaBand(1) <= freq, 1);
                deltaEnd = find(obj.deltaBand(2) > freq, 1, 'last');
                betaStart = find(obj.betaBand(1) <= freq, 1);
                betaEnd = find(obj.betaBand(2) > freq, 1, 'last');
                
                % Compute band powers
                deltaSpectrum = sum(pxx(deltaStart:deltaEnd, :), 1);
                betaSpectrum = sum(pxx(betaStart:betaEnd, :), 1);
                
                % Moving averages (using the same moving function as SpectralTrainClass)
                if exist('moving', 'file')
                    deltaMovingRatio = deltaSpectrum ./ moving(deltaSpectrum, obj.numMovingAvg30secEpochs)';
                    betaMovingRatio = betaSpectrum ./ moving(betaSpectrum, obj.numMovingAvg30secEpochs)';
                else
                    % Fallback: simple moving average
                    deltaMovingRatio = deltaSpectrum ./ movmean(deltaSpectrum, obj.numMovingAvg30secEpochs);
                    betaMovingRatio = betaSpectrum ./ movmean(betaSpectrum, obj.numMovingAvg30secEpochs);
                end
                
                % Identify artifacts
                obj.deltaArtifactMask = deltaMovingRatio > obj.artifactTH(1);
                obj.betaArtifactMask = betaMovingRatio > obj.artifactTH(2);
                obj.artifactMask = or(obj.deltaArtifactMask, obj.betaArtifactMask);
                
                % Apply sleep stage restriction if provided
                if nargin >= 4 && ~isempty(sleepStages)
                    validStages = sleepStages(1:min(length(sleepStages), numCompleteEpochs));
                    wakeMask = validStages == 0;
                    obj.artifactMask(wakeMask) = false; % Don't count wake as artifacts
                end
                
                fprintf('Artifact detection complete:\n');
                fprintf('  - Delta artifacts: %d epochs\n', sum(obj.deltaArtifactMask));
                fprintf('  - Beta artifacts: %d epochs\n', sum(obj.betaArtifactMask));
                fprintf('  - Total artifacts: %d epochs (%.1f%%)\n', ...
                    sum(obj.artifactMask), mean(obj.artifactMask)*100);
                
            else
                warning('Signal too short for artifact detection (need at least 30 seconds)');
                obj.artifactMask = false(1, ceil(length(x)/samplesPer30sec));
                obj.deltaArtifactMask = obj.artifactMask;
                obj.betaArtifactMask = obj.artifactMask;
            end
            
            % Prepare artifact info structure
            artifactInfo = struct();
            artifactInfo.deltaArtifacts = sum(obj.deltaArtifactMask);
            artifactInfo.betaArtifacts = sum(obj.betaArtifactMask);
            artifactInfo.totalArtifacts = sum(obj.artifactMask);
            artifactInfo.artifactPercentage = mean(obj.artifactMask) * 100;
            artifactInfo.numEpochs = length(obj.artifactMask);
        end
        
        function mask = getArtifactMaskForSignal(obj, signalData, fs, epochDuration)
            % Create artifact mask at signal sampling rate
            if isempty(obj.artifactMask)
                mask = false(1, length(signalData));
                return;
            end
            
            samplesPerEpoch = epochDuration * fs;
            numEpochs = length(obj.artifactMask);
            mask = false(1, length(signalData));
            
            for epoch = 1:min(numEpochs, ceil(length(signalData)/samplesPerEpoch))
                if obj.artifactMask(epoch)
                    startSample = (epoch-1) * samplesPerEpoch + 1;
                    endSample = min(epoch * samplesPerEpoch, length(signalData));
                    mask(startSample:endSample) = true;
                end
            end
        end
        
        function cleanData = applyArtifactMask(obj, data, fs)
            % Remove artifact-contaminated segments from data
            if isempty(obj.artifactMask)
                cleanData = data;
                return;
            end
            
            if iscell(data)
                cleanData = cell(size(data));
                for i = 1:length(data)
                    cleanData{i} = obj.applyMaskToChannel(data{i}, fs);
                end
            else
                cleanData = zeros(size(data));
                for i = 1:size(data, 1)
                    cleanData(i, :) = obj.applyMaskToChannel(data(i, :), fs);
                end
            end
        end
        
        function cleanChannel = applyMaskToChannel(obj, channelData, fs)
            % Apply artifact mask to single channel
            artifactSignalMask = obj.getArtifactMaskForSignal(channelData, fs, 30);
            cleanChannel = channelData;
            cleanChannel(artifactSignalMask) =  NaN; % ✅ Use NaN for explicit exclusion
        end
        
        function summary = getCleaningSummary(obj)
            % Get comprehensive summary of data cleaning
            summary = struct();
            summary.ecgDecontaminationApplied = obj.ecgDecontaminationApplied;
            summary.ecgContaminationScore = obj.ecgContaminationScore;
            
            if ~isempty(obj.artifactMask)
                summary.totalArtifacts = sum(obj.artifactMask);
                summary.artifactPercentage = mean(obj.artifactMask) * 100;
                summary.deltaArtifacts = sum(obj.deltaArtifactMask);
                summary.betaArtifacts = sum(obj.betaArtifactMask);
            else
                summary.totalArtifacts = 0;
                summary.artifactPercentage = 0;
                summary.deltaArtifacts = 0;
                summary.betaArtifacts = 0;
            end
            
            summary.cleanDataPercentage = 100 - summary.artifactPercentage;
        end
    end
        methods (Access = private)
        function isGoodQuality = checkECGQuality(obj, ecgSignal, fs)
            % Check ECG signal quality before decontamination
            if isempty(ecgSignal) || length(ecgSignal) < fs
                fprintf('ECG signal too short or empty - skipping decontamination\n');
                isGoodQuality = false;
                return;
            end
            
            % Check for flat lines
            if std(ecgSignal) < 0.001
                fprintf('ECG signal appears flat (std=%.6f) - skipping decontamination\n', std(ecgSignal));
                isGoodQuality = false;
                return;
            end
            
            % Check for excessive noise using Median Absolute Deviation
            try
                signalMAD = mad(ecgSignal, 1);
                diffMAD = mad(diff(ecgSignal), 1);
                if diffMAD > 0
                    noiseLevel = signalMAD / diffMAD;
                    if noiseLevel > 10
                        fprintf('ECG signal too noisy (noise level: %.2f) - skipping decontamination\n', noiseLevel);
                        isGoodQuality = false;
                        return;
                    end
                end
            catch
                % If MAD calculation fails, use standard deviation
                noiseLevel = std(ecgSignal) / std(diff(ecgSignal));
                if noiseLevel > 10
                    fprintf('ECG signal too noisy (noise level: %.2f) - skipping decontamination\n', noiseLevel);
                    isGoodQuality = false;
                    return;
                end
            end
            
            % Additional check: signal range
            signalRange = range(ecgSignal);
            if signalRange < 0.1
                fprintf('ECG signal range too small (%.4f) - skipping decontamination\n', signalRange);
                isGoodQuality = false;
                return;
            end
            
            fprintf('ECG signal quality check passed\n');
            isGoodQuality = true;
        end
    end
end