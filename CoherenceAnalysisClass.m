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
            
            eegChannelIndices = [];
            eegChannelNames = {};
            
            for ch = 1:length(allChannels)
                channelName = strtrim(allChannels{ch});
                chIdx = find(strcmpi(obj.mappedChannelNames, channelName), 1);
                
                if ~isempty(chIdx)
                    eegChannelIndices(end+1) = chIdx;
                    eegChannelNames{end+1} = obj.mappedChannelNames{chIdx};
                    fprintf('Matched channel: "%s" -> "%s" (index %d)\n', channelName, obj.mappedChannelNames{chIdx}, chIdx);
                else
                    fprintf('WARNING: Could not find channel: "%s"\n', channelName);
                end
            end
            
            if isempty(eegChannelIndices)
                warning('No specified channels found for analysis');
                return;
            end
            
            fprintf('Targeted cleaning for %d EEG channels: %s\n', ...
                length(eegChannelIndices), strjoin(eegChannelNames, ', '));
            
            [cleanData, artifactInfo] = obj.performTargetedCleaning(eegChannelIndices, eegChannelNames);
            
            for i = 1:length(eegChannelIndices)
                obj.data{eegChannelIndices(i)} = cleanData{i};
            end
            
            obj.cleaningSummary = obj.artifactDetector.getCleaningSummary();
            
            obj.coherenceResults = struct();
            obj.coherenceResults.pairs = pairs;
            obj.coherenceResults.coherence = struct();
            obj.coherenceResults.sleepStages = struct();
            obj.coherenceResults.sleepPeriods = struct();
            obj.coherenceResults.analysisParameters = obj.coherenceParams;
            
            for i = 1:length(pairs)
                pair = pairs{i};
                channelNames = strsplit(pair, '-');
                
                if length(channelNames) == 2
                    ch1 = strtrim(channelNames{1});
                    ch2 = strtrim(channelNames{2});
                    
                    idx1 = find(strcmp(obj.mappedChannelNames, ch1), 1);
                    idx2 = find(strcmp(obj.mappedChannelNames, ch2), 1);
                    
                    if ~isempty(idx1) && ~isempty(idx2)
                        fprintf('Analyzing coherence pair: %s - %s\n', ch1, ch2);
                        
                        if ~isempty(obj.numericHypnogram)
                            obj.calculateSleepPeriodCoherence(idx1, idx2, pair);
                        else
                            globalCoherence = obj.calculateComprehensiveCoherence(idx1, idx2);
                            obj.coherenceResults.coherence.(obj.sanitizeFieldName(pair)) = globalCoherence;
                        end
                        
                        if ~isempty(obj.numericHypnogram)
                            obj.calculateStageSpecificCoherence(idx1, idx2, pair);
                        end
                    else
                        fprintf('WARNING: Pair %s not found in data (ch1: %s, ch2: %s)\n', pair, ch1, ch2);
                    end
                else
                    fprintf('WARNING: Invalid pair format: %s\n', pair);
                end
            end
            
            fprintf('Coherence analysis completed for %d pairs\n', length(pairs));
            obj.printSummaryStatistics();
        end

        function saveResults(obj, outputFile)
            if isempty(obj.coherenceResults)
                error('No results to save. Run analysis first.');
            end
            
            fprintf('Saving coherence results to: %s\n', outputFile);
            
            if exist(outputFile, 'file')
                delete(outputFile);
            end
            
            resultsTable = obj.createComprehensiveResultsTable();
            writetable(resultsTable, outputFile, 'Sheet', 'Coherence_Results');
            
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
                
                if isfield(obj.coherenceResults.coherence, sanitizedPair)
                    coherenceData = obj.coherenceResults.coherence.(sanitizedPair);
                    
                    fprintf('\n=== COHERENCE METRICS FOR %s ===\n', firstPair);
                    fprintf('Global Mean Coherence: %.3f\n', coherenceData.meanCoherence);
                    fprintf('Peak Coherence: %.3f at %.1f Hz\n', ...
                        coherenceData.peakCoherence, coherenceData.peakFrequency);
                    
                    fprintf('Band Coherence:\n');
                    fprintf('  Delta (1-4 Hz): %.3f\n', coherenceData.bandCoherence.Delta);
                    fprintf('  Theta (4-8 Hz): %.3f\n', coherenceData.bandCoherence.Theta);
                    fprintf('  Alpha (8-12 Hz): %.3f\n', coherenceData.bandCoherence.Alpha);
                    fprintf('  Sigma (12-15 Hz): %.3f\n', coherenceData.bandCoherence.Sigma);
                    fprintf('  Beta (15-30 Hz): %.3f\n', coherenceData.bandCoherence.Beta);
                    fprintf('  Gamma (30-45 Hz): %.3f\n', coherenceData.bandCoherence.Gamma);
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
                'Delta',    [1.0, 4.0];
                'Theta',    [4.0, 8.0];
                'Alpha',    [8.0, 12.0];
                'Sigma',    [12.0, 15.0];
                'Beta',     [15.0, 30.0];
                'Gamma',    [30.0, 45.0];
                };
            
            params.coherenceThreshold = 0.5;
            params.confidenceLevel = 0.95;
            params.nfft = 1024;
            params.frequencyResolution = obj.fs(1) / params.nfft;
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
            
            globalCoherence = obj.calculateComprehensiveCoherence(idx1, idx2);
            obj.coherenceResults.coherence.(sanitizedPair) = globalCoherence;
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
            
            stages = {'N1', 'N2', 'N3', 'REM', 'WASO'};
            sanitizedPair = obj.sanitizeFieldName(pairName);
            obj.coherenceResults.sleepStages.(sanitizedPair) = struct();
            
            fprintf('  Stage-specific coherence analysis (%d epochs):\n', numCompleteEpochs);
            
            for s = 1:length(stages)
                stage = stages{s};
                
                if strcmp(stage, 'WASO')
                    stageMask = obj.createWASOMask(length(data1));
                    stageEpochs = sum(stageMask) / samplesPerEpoch;
                else
                    stageMask = obj.stageMasks.(stage);
                    stageEpochs = sum(stageMask(1:numCompleteEpochs));
                end
                
                if stageEpochs > 0
                    fprintf('    %s: %.1f epochs\n', stage, stageEpochs);
                    
                    stageData1 = [];
                    stageData2 = [];
                    
                    if strcmp(stage, 'WASO')
                        stageData1 = data1(stageMask);
                        stageData2 = data2(stageMask);
                    else
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
                        obj.coherenceResults.sleepStages.(sanitizedPair).(stage) = stageCoherence;
                        fprintf('      Coherence: mean=%.3f, peak=%.3f@%.1fHz\n', ...
                            stageCoherence.meanCoherence, stageCoherence.peakCoherence, stageCoherence.peakFrequency);
                    else
                        fprintf('      Insufficient clean data (%.1f s < 30 s)\n', length(stageData1)/fs);
                    end
                end
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
            result.bandCoherence = obj.calculateBandCoherence(cxy, f);
            result.coherenceRatios = obj.calculateCoherenceRatios(result.bandCoherence);
            result.dataLength = length(data1) / fs;
            result.validWindows = length(cxy);
        end
        
        function resultsTable = createComprehensiveResultsTable(obj)
            pairs = obj.coherenceResults.pairs;
            
            resultsTable = table();
            
            for i = 1:length(pairs)
                pair = pairs{i};
                sanitizedPair = obj.sanitizeFieldName(pair);
                
                if isfield(obj.coherenceResults.coherence, sanitizedPair)
                    coherenceData = obj.coherenceResults.coherence.(sanitizedPair);
                    
                    globalRow = table();
                    globalRow.Pair = {pair};
                    globalRow.SleepStage = {'Global'};
                    globalRow.MeanCoherence = coherenceData.meanCoherence;
                    globalRow.MedianCoherence = coherenceData.medianCoherence;
                    globalRow.PeakCoherence = coherenceData.peakCoherence;
                    globalRow.PeakFrequency_Hz = coherenceData.peakFrequency;
                    globalRow.CoherenceBandwidth_Hz = coherenceData.coherenceBandwidth;
                    globalRow.CoherenceArea = coherenceData.coherenceArea;
                    globalRow.CoherenceVariance = coherenceData.coherenceVariance;
                    globalRow.DominantFrequency_Hz = coherenceData.dominantFrequency;
                    globalRow.SpectralEntropy = coherenceData.spectralEntropy;
                    
                    bands = fieldnames(coherenceData.bandCoherence);
                    for b = 1:length(bands)
                        bandName = bands{b};
                        globalRow.(['Coherence_' bandName]) = coherenceData.bandCoherence.(bandName);
                    end
                    
                    if isfield(coherenceData, 'coherenceRatios')
                        ratios = fieldnames(coherenceData.coherenceRatios);
                        for r = 1:length(ratios)
                            ratioName = ratios{r};
                            globalRow.(['Ratio_' ratioName]) = coherenceData.coherenceRatios.(ratioName);
                        end
                    end
                    
                    globalRow.DataLength_sec = coherenceData.dataLength;
                    globalRow.ValidWindows = coherenceData.validWindows;
                    
                    resultsTable = [resultsTable; globalRow];
                end
                
                if isfield(obj.coherenceResults.sleepPeriods, sanitizedPair)
                    periodResults = obj.coherenceResults.sleepPeriods.(sanitizedPair);
                    periods = fieldnames(periodResults);
                    
                    for p = 1:length(periods)
                        period = periods{p};
                        periodCoherence = periodResults.(period);
                        
                        periodRow = table();
                        periodRow.Pair = {pair};
                        periodRow.SleepStage = {period};
                        periodRow.MeanCoherence = periodCoherence.meanCoherence;
                        periodRow.MedianCoherence = periodCoherence.medianCoherence;
                        periodRow.PeakCoherence = periodCoherence.peakCoherence;
                        periodRow.PeakFrequency_Hz = periodCoherence.peakFrequency;
                        periodRow.CoherenceBandwidth_Hz = periodCoherence.coherenceBandwidth;
                        periodRow.CoherenceArea = periodCoherence.coherenceArea;
                        periodRow.CoherenceVariance = periodCoherence.coherenceVariance;
                        periodRow.DominantFrequency_Hz = periodCoherence.dominantFrequency;
                        periodRow.SpectralEntropy = periodCoherence.spectralEntropy;
                        
                        bands = fieldnames(periodCoherence.bandCoherence);
                        for b = 1:length(bands)
                            bandName = bands{b};
                            periodRow.(['Coherence_' bandName]) = periodCoherence.bandCoherence.(bandName);
                        end
                        
                        periodRow.DataLength_sec = periodCoherence.dataLength;
                        periodRow.ValidWindows = periodCoherence.validWindows;
                        
                        resultsTable = [resultsTable; periodRow];
                    end
                end
                
                if isfield(obj.coherenceResults.sleepStages, sanitizedPair)
                    stageResults = obj.coherenceResults.sleepStages.(sanitizedPair);
                    stages = fieldnames(stageResults);
                    
                    for s = 1:length(stages)
                        stage = stages{s};
                        stageCoherence = stageResults.(stage);
                        
                        stageRow = table();
                        stageRow.Pair = {pair};
                        stageRow.SleepStage = {stage};
                        stageRow.MeanCoherence = stageCoherence.meanCoherence;
                        stageRow.MedianCoherence = stageCoherence.medianCoherence;
                        stageRow.PeakCoherence = stageCoherence.peakCoherence;
                        stageRow.PeakFrequency_Hz = stageCoherence.peakFrequency;
                        stageRow.CoherenceBandwidth_Hz = stageCoherence.coherenceBandwidth;
                        stageRow.CoherenceArea = stageCoherence.coherenceArea;
                        stageRow.CoherenceVariance = stageCoherence.coherenceVariance;
                        stageRow.DominantFrequency_Hz = stageCoherence.dominantFrequency;
                        stageRow.SpectralEntropy = stageCoherence.spectralEntropy;
                        
                        bands = fieldnames(stageCoherence.bandCoherence);
                        for b = 1:length(bands)
                            bandName = bands{b};
                            stageRow.(['Coherence_' bandName]) = stageCoherence.bandCoherence.(bandName);
                        end
                        
                        stageRow.DataLength_sec = stageCoherence.dataLength;
                        stageRow.ValidWindows = stageCoherence.validWindows;
                        stageRow.StageEpochs = stageCoherence.stageEpochs;
                        
                        resultsTable = [resultsTable; stageRow];
                    end
                end
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