classdef MicrostateAnalysisClass < handle
    % MicrostateAnalysisClass: Full EEG microstate analysis pipeline.
    % Uses same channel mapping and data loading as SpindleDetectionClass

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
    end

    methods
        function obj = MicrostateAnalysisClass(edfFile, params)
            if nargin < 2
                params = struct();
            end
            obj.edfPath = edfFile;
            
            % Use the same EDF loading approach as SpindleDetectionClass
            try
                fprintf('Loading EDF file: %s\n', edfFile);
                obj.edfLoader = BlockEdfLoadClass(edfFile);
                obj.edfLoader.numCompToLoad = 3;
                obj.edfLoader.SWAP_MIN_MAX = 1;
                obj.edfLoader = obj.edfLoader.blockEdfLoad;
            catch ME
                error('Error loading EDF file with BlockEdfLoadClass: %s', ME.message);
            end
            
            obj.setupMappedChannels();
            obj.setDefaultParams(params);
            obj.microstateResults = [];
        obj.artifactDetector = ArtifactDetectionClass();
        end

        function runAnalysis(obj)
                fprintf('Starting microstate analysis with comprehensive data cleaning...\n');
            
            % Perform comprehensive data cleaning
            [cleanData, artifactInfo] = obj.artifactDetector.fullDataCleaning(...
                obj.data, obj.channelLabels, obj.fs, []);
            
            % Update data with cleaned version
            obj.data = cleanData;
            obj.cleaningSummary = obj.artifactDetector.getCleaningSummary();
            
            % Continue with microstate analysis...
            [dataProc, fsNew] = obj.preprocessData(obj.data, obj.fs);
            
            if isempty(obj.data)
                warning('No data to process.');
                return;
            end

            fprintf('Starting microstate analysis on %d channels...\n', size(obj.data, 1));
            
            [dataProc, fsNew] = obj.preprocessData(obj.data, obj.fs);
            
            % Calculate GFP and find peaks
            gfp = sqrt(mean(dataProc.^2, 1));
            gfpPeaks = obj.findGFPPeaks(gfp, fsNew);

            fprintf('Found %d GFP peaks\n', length(gfpPeaks));

            if length(gfpPeaks) < 10
                warning('Too few GFP peaks (<10) for reliable clustering.');
                obj.microstateResults = [];
                return;
            end

            % Extract maps at GFP peaks with safety checks
            maps = dataProc(:, gfpPeaks);
            
            % Remove any maps with NaN or Inf values
            validMaps = all(isfinite(maps), 1);
            maps = maps(:, validMaps);
            gfpPeaks = gfpPeaks(validMaps);
            
            if size(maps, 2) < 10
                warning('Too few valid GFP peaks after cleaning.');
                obj.microstateResults = [];
                return;
            end

            fprintf('Using %d valid GFP peaks for clustering\n', size(maps, 2));

            % Polarity correction
            maps = maps .* sign(maps(1,:));

            % K-means clustering with robust error handling
            k = obj.microstateParams.numMaps;
            
            % Ensure we have enough data points for k-means
            if size(maps, 2) < k
                warning('Not enough GFP peaks for %d clusters. Reducing to %d clusters.', k, size(maps, 2));
                k = max(2, size(maps, 2));
            end

            try
                opts = statset('MaxIter', 1000, 'Display', 'off', 'UseParallel', false);
                [clusterIdx, C, sumd] = kmeans(maps', k, 'Replicates', 5, 'Options', opts, 'EmptyAction', 'singleton');
            catch ME
                warning('K-means failed: %s. Trying with fewer replicates.', ME.message);
                try
                    [clusterIdx, C, sumd] = kmeans(maps', k, 'Replicates', 2, 'Options', opts, 'EmptyAction', 'singleton');
                catch ME2
                    warning('K-means completely failed: %s', ME2.message);
                    obj.microstateResults = [];
                    return;
                end
            end

            % Create final maps from clusters
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

            % Backfitting segmentation with robustness
            seg = zeros(1, size(dataProc,2));
            for t = 1:size(dataProc,2)
                x = dataProc(:,t);
                if norm(x) == 0 || any(~isfinite(x))
                    continue;
                end
                x = x / norm(x);
                corr = finalMaps' * x;
                [~, seg(t)] = max(corr);
            end

            % Calculate GEV with comprehensive error checking
            totalGEV = 0;
            mapGEV = zeros(1,k);
            totalVariance = sum(dataProc.^2, 'all');

            if totalVariance == 0 || ~isfinite(totalVariance)
                warning('Invalid total variance: %f', totalVariance);
                totalGEV = 0;
                mapGEV = zeros(1,k);
            else
                validSegments = 0;
                for i = 1:k
                    idx = seg == i;
                    if sum(idx) > 10  % Require minimum segments for meaningful GEV
                        x = dataProc(:,idx);
                        segmentVariance = sum(x.^2, 'all');
                        if segmentVariance > 0 && isfinite(segmentVariance)
                            map = finalMaps(:,i);
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
                
                if validSegments > 0
                    totalGEV = totalGEV / totalVariance;
                else
                    totalGEV = 0;
                end
            end

            % Final sanity checks
            if ~isfinite(totalGEV) || totalGEV < 0 || totalGEV > 1
                fprintf('Correcting invalid GEV: %.3f -> ', totalGEV);
                totalGEV = max(0, min(1, totalGEV));
                if ~isfinite(totalGEV)
                    totalGEV = 0;
                end
                fprintf('%.3f\n', totalGEV);
            end
            
            mapGEV(~isfinite(mapGEV)) = 0;
            mapGEV = max(0, min(1, mapGEV));

            % Store results
            obj.microstateResults = struct(...
                'templates', finalMaps, ...
                'segmentation', seg, ...
                'gfpPeaks', gfpPeaks, ...
                'mapGEV', mapGEV, ...
                'totalGEV', totalGEV, ...
                'numMaps', k, ...
                'fs', fsNew, ...
                'channelLabels', {obj.channelLabels} ...
            );
            
            fprintf('Microstate analysis completed successfully\n');
            fprintf('Total GEV: %.3f\n', totalGEV);
            fprintf('Map GEVs: %s\n', mat2str(mapGEV, 3));
        end

        function saveResults(obj, outputFile)
            if isempty(obj.microstateResults)
                warning('No results to save.');
                return;
            end
            microstateResults = obj.microstateResults;
            save(outputFile, 'microstateResults');
            fprintf('Saved microstate results to: %s\n', outputFile);
        end

        function saveResultsToExcel(obj, outputFile)
            if isempty(obj.microstateResults)
                warning('No results to save.');
                return;
            end
            
            R = obj.microstateResults;
            
            % Create summary table
            summaryData = {
                'Number of Maps', R.numMaps;
                'Total GEV', R.totalGEV;
                'Sampling Rate', R.fs;
                'Number of Channels', length(R.channelLabels);
                'Number of GFP Peaks', length(R.gfpPeaks);
                'Analysis Duration (s)', size(obj.data, 2) / R.fs;
            };
            
            for i = 1:R.numMaps
                summaryData{end+1, 1} = sprintf('Map %d GEV', i);
                summaryData{end, 2} = R.mapGEV(i);
            end
            
            summaryTable = cell2table(summaryData, 'VariableNames', {'Parameter', 'Value'});
            
            % Create channel information table
            channelTable = table((1:length(R.channelLabels))', R.channelLabels', ...
                'VariableNames', {'Channel_Index', 'Channel_Label'});
            
            % Create microstate template table (maps)
            mapTable = array2table(R.templates, ...
                'VariableNames', arrayfun(@(x) sprintf('Map_%d', x), 1:R.numMaps, 'UniformOutput', false));
            mapTable.Channel = R.channelLabels';
            
            % Create GFP peaks table (first 1000 peaks as example)
            maxPeaksToSave = min(1000, length(R.gfpPeaks));
            gfpTable = table((1:maxPeaksToSave)', R.gfpPeaks(1:maxPeaksToSave)', ...
                'VariableNames', {'Peak_Index', 'Sample_Index'});
            
            % Write to Excel file with multiple sheets
            writetable(summaryTable, outputFile, 'Sheet', 'Summary');
            writetable(channelTable, outputFile, 'Sheet', 'Channels');
            writetable(mapTable, outputFile, 'Sheet', 'Microstate_Maps');
            writetable(gfpTable, outputFile, 'Sheet', 'GFP_Peaks');
            
            fprintf('Saved microstate results to Excel: %s\n', outputFile);
        end
    end

    methods (Access = private)
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
            
            % Get sampling rate (same as spindle detection)
            obj.fs = obj.getSamplingRate(1);
            
            % Select channels for microstate analysis
            obj.selectMicrostateChannels();
            
            fprintf('Microstate channels: %s\n', strjoin(obj.channelLabels, ', '));
            fprintf('Sampling rate: %.1f Hz\n', obj.fs);
            fprintf('Data size: %d channels x %d samples\n', size(obj.data, 1), size(obj.data, 2));
        end

        function selectMicrostateChannels(obj)
            % Select appropriate channels for microstate analysis
            targetChannels = {'F3-M2', 'F4-M1', 'C3-M2', 'C4-M1', 'O1-M2', 'O2-M1'};
            
            availableChannels = {};
            channelIndices = [];
            
            for i = 1:length(targetChannels)
                idx = find(strcmp(obj.channelLabels, targetChannels{i}));
                if ~isempty(idx)
                    availableChannels{end+1} = targetChannels{i};
                    channelIndices(end+1) = idx(1);
                    fprintf('Selected channel: %s\n', targetChannels{i});
                end
            end
            
            if isempty(availableChannels)
                % Fallback: use any available EEG channels
                fprintf('No standard bipolar channels found. Using all available EEG channels...\n');
                eegPatterns = {'F3', 'F4', 'C3', 'C4', 'O1', 'O2', 'Fz', 'Cz', 'Pz'};
                for i = 1:length(obj.channelLabels)
                    for j = 1:length(eegPatterns)
                        if contains(obj.channelLabels{i}, eegPatterns{j})
                            availableChannels{end+1} = obj.channelLabels{i};
                            channelIndices(end+1) = i;
                            fprintf('Selected EEG channel: %s\n', obj.channelLabels{i});
                            break;
                        end
                    end
                end
            end
            
            if isempty(availableChannels)
                error('No suitable EEG channels found for microstate analysis.');
            end
            
            % Update data and channel labels to only include selected channels
            if iscell(obj.data)
                % Data is in cell array format
                selectedData = zeros(length(channelIndices), length(obj.data{1}));
                for i = 1:length(channelIndices)
                    selectedData(i, :) = obj.data{channelIndices(i)};
                end
                obj.data = selectedData;
            else
                % Data is in matrix format
                obj.data = obj.data(channelIndices, :);
            end
            obj.channelLabels = availableChannels;
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

        function fs = getSamplingRate(obj, channelIndex)
            % Get sampling rate using same method as SpindleDetectionClass
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
            % Set microstate analysis parameters
            dp = struct();
            dp.numMaps = 4;
            dp.gfpPeakDistance = 0.05; % Increased from 0.02 for fewer peaks
            dp.filterBand = [1 40];
            dp.downsampleFs = 128; % Changed to 128 for proper downsampling from 256 Hz
            if isfield(p,'numMaps'), dp.numMaps = p.numMaps; end
            if isfield(p,'gfpPeakDistance'), dp.gfpPeakDistance = p.gfpPeakDistance; end
            if isfield(p,'filterBand'), dp.filterBand = p.filterBand; end
            if isfield(p,'downsampleFs'), dp.downsampleFs = p.downsampleFs; end
            obj.microstateParams = dp;
            
            fprintf('Microstate parameters:\n');
            fprintf('  Number of maps: %d\n', dp.numMaps);
            fprintf('  GFP peak distance: %.3f s\n', dp.gfpPeakDistance);
            fprintf('  Filter band: %.1f-%.1f Hz\n', dp.filterBand(1), dp.filterBand(2));
            fprintf('  Downsample to: %.1f Hz\n', dp.downsampleFs);
        end

        function [dataOut, fsOut] = preprocessData(obj, data, fs)
            dp = obj.microstateParams;
            
            % Convert to double and check for invalid values
            data = double(data);
            if any(~isfinite(data(:)))
                warning('Non-finite values found in data. Replacing with zeros.');
                data(~isfinite(data)) = 0;
            end
            
            % Bandpass filter
            [b,a] = butter(2, dp.filterBand/(fs/2), 'bandpass');
            dataFilt = filtfilt(b, a, data');
            dataFilt = dataFilt';
            
            % Downsample
            if fs > dp.downsampleFs
                ratio = fs / dp.downsampleFs;
                dataOut = resample(dataFilt', 1, round(ratio))';
                fsOut = fs / round(ratio);
                fprintf('Downsampled: %.1f Hz -> %.1f Hz\n', fs, fsOut);
            else
                dataOut = dataFilt;
                fsOut = fs;
                fprintf('No downsampling needed: %.1f Hz\n', fs);
            end
            
            % Remove DC offset and check again
            dataOut = dataOut - mean(dataOut, 2);
            
            if any(~isfinite(dataOut(:)))
                warning('Non-finite values after preprocessing. Replacing with zeros.');
                dataOut(~isfinite(dataOut)) = 0;
            end
            
            fprintf('Preprocessing complete: %d channels, %.1f Hz, %d samples\n', ...
                size(dataOut, 1), fsOut, size(dataOut, 2));
        end

        function peaks = findGFPPeaks(obj, gfp, fs)
            % Find GFP peaks for microstate analysis
            dp = obj.microstateParams;
            minDist = max(1, round(dp.gfpPeakDistance * fs));
            [pks, locs] = findpeaks(gfp, 'MinPeakDistance', minDist);
            [~, idx] = sort(pks, 'descend');
            peaks = locs(idx);
            
            fprintf('Found %d GFP peaks\n', length(peaks));
        end
    end
end