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
            
            % Extract ECG signal
            if iscell(data)
                ecgSignal = data{ecgChannel};
                eegSignals = data;
                eegSignals(ecgChannel) = []; % Remove ECG from EEG signals
                eegLabels = signalLabels;
                eegLabels(ecgChannel) = [];
            else
                ecgSignal = data(ecgChannel, :);
                eegSignals = data(setdiff(1:size(data,1), ecgChannel), :);
                eegLabels = signalLabels(setdiff(1:length(signalLabels), ecgChannel));
            end
            
            try
                % Use the same ecgDecont function as in SpectralTrainClass
                if iscell(eegSignals)
                    cleanEEG = ecgDecont(eegSignals, fs, ecgSignal, fs, eegLabels);
                else
                    % Convert matrix to cell array for ecgDecont
                    eegCell = cell(1, size(eegSignals, 1));
                    for i = 1:size(eegSignals, 1)
                        eegCell{i} = eegSignals(i, :);
                    end
                    cleanEEG = ecgDecont(eegCell, fs, ecgSignal, fs, eegLabels);
                    
                    % Convert back to matrix if input was matrix
                    if ~iscell(data)
                        cleanEEG = cell2mat(cleanEEG');
                    end
                end
                
                % Reconstruct data with cleaned EEG and original ECG
                if iscell(data)
                    cleanData = cleanEEG;
                    % Add ECG channel back if needed
                    % cleanData{end+1} = ecgSignal;
                else
                    cleanData = zeros(size(data));
                    cleanData(setdiff(1:size(data,1), ecgChannel), :) = cleanEEG;
                    cleanData(ecgChannel, :) = ecgSignal; % Keep original ECG
                end
                
                obj.ecgDecontaminationApplied = true;
                obj.estimateECGContamination(data, cleanData);
                
                fprintf('ECG decontamination completed successfully\n');
                
            catch ME
                warning('ECG decontamination failed: %s. Using original data.', ME.message);
                cleanData = data;
                obj.ecgDecontaminationApplied = false;
            end
        end
        
        function ecgChannel = findECGChannel(obj, signalLabels)
            % Find ECG channel using flexible matching (same as SpectralTrainClass)
            ecgChannel = [];
            
            for i = 1:length(signalLabels)
                currentLabel = upper(signalLabels{i});
                
                % Exact matches
                if any(strcmpi(signalLabels{i}, obj.ecgName))
                    ecgChannel = i;
                    break;
                end
                
                % Partial matches
                for j = 1:length(obj.ecgName)
                    if contains(currentLabel, upper(obj.ecgName{j}))
                        ecgChannel = i;
                        break;
                    end
                end
                
                if ~isempty(ecgChannel)
                    break;
                end
            end
            
            % If no match found, try common variations
            if isempty(ecgChannel)
                ecgPatterns = {'ECG', 'EKG', 'ELECTROCARDIO', 'ELECTRO-CARDIO'};
                for i = 1:length(signalLabels)
                    currentLabel = upper(signalLabels{i});
                    for j = 1:length(ecgPatterns)
                        if contains(currentLabel, ecgPatterns{j})
                            ecgChannel = i;
                            fprintf('Found potential ECG channel: %s\n', signalLabels{i});
                            break;
                        end
                    end
                    if ~isempty(ecgChannel)
                        break;
                    end
                end
            end
        end
        
        function estimateECGContamination(obj, originalData, cleanedData)
            % Estimate ECG contamination level by comparing original and cleaned data
            try
                if iscell(originalData) && iscell(cleanedData)
                    % Use first channel for estimation
                    orig = originalData{1};
                    clean = cleanedData{1};
                else
                    orig = originalData(1, :);
                    clean = cleanedData(1, :);
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
                refChannel = 1;
                x = data{refChannel};
            else
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
            cleanChannel(artifactSignalMask) = 0; % Zero out artifact periods
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
end