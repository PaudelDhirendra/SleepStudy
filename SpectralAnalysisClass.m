classdef SpectralAnalysisClass < handle
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
        spectralResults
        artifactDetector
        cleaningSummary
        allChannelData
        allChannelLabels
        sleepCycles
        globalArtifactMask
        
        % New properties for enhanced functionality
        originalData
        stage2Mask
        stage3Mask
    end

    methods
        function obj = SpectralAnalysisClass(edfPath, xmlPath, params)
            if nargin < 3
                params = struct();
            end
            obj.edfPath = edfPath;
            obj.xmlPath = xmlPath;
            obj.params = params;
            
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
            obj.spectralResults = [];
            
            % Initialize artifact detector with ECG decontamination
            obj.artifactDetector = ArtifactDetectionClass();
            if isfield(params, 'ecgName')
                obj.artifactDetector.setECGParameters(params.ecgName, true);
            else
                % Auto-detect ECG channel
                obj.artifactDetector.setECGParameters([], true);
            end
            
            % Detect sleep cycles if hypnogram available
            if ~isempty(obj.numericHypnogram)
                obj.detectSleepCycles();
            end
        end

        function runAnalysis(obj, channels)
            fprintf('Starting spectral analysis focused on sleep periods...\n');
            
            % Identify channels for analysis
            eegChannelIndices = [];
            eegChannelNames = {};
            
            availableChannels = obj.mappedChannelNames;
            
            fprintf('Available channels for matching:\n');
            for i = 1:length(availableChannels)
                fprintf('  %d: "%s"\n', i, availableChannels{i});
            end
            
            fprintf('Requested channels:\n');
            for i = 1:length(channels)
                fprintf('  %d: "%s"\n', i, channels{i});
            end
            
            % Channel matching - use the MAPPED names
            for ch = 1:length(channels)
                channelName = strtrim(channels{ch});
                chIdx = find(strcmpi(availableChannels, channelName), 1);
                
                if ~isempty(chIdx)
                    eegChannelIndices(end+1) = chIdx;
                    eegChannelNames{end+1} = availableChannels{chIdx};
                    fprintf('Matched channel: "%s" -> "%s" (index %d)\n', channelName, availableChannels{chIdx}, chIdx);
                else
                    fprintf('WARNING: Could not find channel: "%s"\n', channelName);
                    % Debug: Show similar channels
                    similarChannels = {};
                    for j = 1:length(availableChannels)
                        if contains(availableChannels{j}, channelName) || contains(channelName, availableChannels{j})
                            similarChannels{end+1} = availableChannels{j};
                        end
                    end
                    if ~isempty(similarChannels)
                        fprintf('  Similar available channels: %s\n', strjoin(similarChannels, ', '));
                    end
                end
            end
            
            if isempty(eegChannelIndices)
                warning('No specified channels found for analysis.');
                return;
            end
            
            fprintf('Advanced cleaning for %d EEG channels: %s\n', ...
                length(eegChannelIndices), strjoin(eegChannelNames, ', '));
            
            % Perform comprehensive artifact detection and cleaning
            [cleanData, artifactInfo] = obj.performTargetedCleaning(eegChannelIndices, eegChannelNames);
            
            % Store cleaned data
            obj.data = cell(1, length(eegChannelIndices));
            for i = 1:length(eegChannelIndices)
                obj.data{i} = cleanData{i};
            end
            obj.channelLabels = eegChannelNames;
            
            obj.cleaningSummary = obj.artifactDetector.getCleaningSummary();
            
            % Initialize results structure - SIMPLIFIED
            obj.spectralResults = struct();
            obj.spectralResults.channels = channels;
            obj.spectralResults.channelIndices = eegChannelIndices;
            obj.spectralResults.bandPower = struct();
            obj.spectralResults.relativePower = struct();
            obj.spectralResults.spectralMetrics = struct();
            obj.cleaningSummary = obj.cleaningSummary;
            
            % Define frequency bands
            freqBands = {
                'Delta',    [0.5, 4.0];
                'Theta',    [4.0, 8.0];
                'Alpha',    [8.0, 12.0];
                'Sigma',    [12.0, 15.0];
                'Beta',     [15.0, 30.0];
                'Gamma',    [30.0, 45.0]
                };
            
            % Perform spectral analysis for each channel
            for ch = 1:length(eegChannelIndices)
                channelName = channels{ch};
                channelData = obj.data{ch};
                fs = obj.fs(1);
                
                fprintf('Analyzing channel: %s\n', channelName);
                
                % Data validation
                if isempty(channelData) || all(channelData == 0)
                    fprintf('Warning: Channel %s has invalid data. Skipping.\n', channelName);
                    continue;
                end
                
                % Remove NaN values
                if any(isnan(channelData))
                    channelData(isnan(channelData)) = 0;
                end
                
                sanitizedName = obj.sanitizeFieldName(channelName);
                
                % ONLY CALCULATE SLEEP PERIOD ANALYSES
                if ~isempty(obj.numericHypnogram)
                    % Calculate SPT, TST, and WASO analysis
                    [tstBandPower, sptBandPower, wasoBandPower, tstTotalPower, sptTotalPower, wasoTotalPower] = ...
                        obj.calculateSleepAnalysis(channelData, channelName, fs, freqBands);
                    
                    % Store SPT results (main sleep period analysis)
                    if ~isempty(sptBandPower)
                        obj.spectralResults.bandPower.(sanitizedName).SPT = sptBandPower;
                        obj.spectralResults.relativePower.(sanitizedName).SPT = ...
                            obj.calculateRelativePower(sptBandPower, sptTotalPower, freqBands);
                    end
                    
                    % Store TST results (sleep only)
                    if ~isempty(tstBandPower)
                        obj.spectralResults.bandPower.(sanitizedName).TST = tstBandPower;
                        obj.spectralResults.relativePower.(sanitizedName).TST = ...
                            obj.calculateRelativePower(tstBandPower, tstTotalPower, freqBands);
                    end
                    
                    % Store WASO as a "stage" for stage-specific analysis
                    if ~isempty(wasoBandPower)
                        obj.spectralResults.bandPower.(sanitizedName).WASO = wasoBandPower;
                        obj.spectralResults.relativePower.(sanitizedName).WASO = ...
                            obj.calculateRelativePower(wasoBandPower, wasoTotalPower, freqBands);
                    end
                    
                    % Calculate stage-specific results (including WASO but NOT general wake)
                    obj.calculateStageSpecificPSD(channelData, channelName, fs, freqBands);
                    
                    % Calculate sleep cycle results
                    if ~isempty(obj.sleepCycles)
                        obj.calculateCycleSpecificPSD(channelData, channelName, fs, freqBands);
                    end
                else
                    fprintf('  No hypnogram available, skipping sleep period analysis\n');
                end
            end
            
            % Calculate spectral ratios and advanced metrics
            obj.calculateAdvancedMetrics(freqBands);
            
            fprintf('Sleep period spectral analysis completed for %d channels\n', length(eegChannelIndices));
            obj.printSummaryStatistics();
        end

        function saveResults(obj, outputFile)
            % Main save method - calls the Excel-specific method
            obj.saveToExcel(outputFile);
        end

        function saveToExcel(obj, outputFile)
            if isempty(obj.spectralResults)
                error('No results to save. Run analysis first.');
            end
            
            fprintf('Saving sleep period spectral results to Excel: %s\n', outputFile);
            
            % Delete existing file
            if exist(outputFile, 'file')
                delete(outputFile);
            end
            
            % 1. Sleep Period Analysis (SPT + TST)
            obj.saveSleepPeriodAnalysisToExcel(outputFile);
            
            % 2. Stage-specific Analysis (including WASO but NOT general wake)
            obj.saveStageAnalysisToExcel(outputFile);
            
            % 3. Sleep Cycle Analysis
            obj.saveCycleAnalysisToExcel(outputFile);
            
                % 4. Regional Power Summary (NEW - ADD THIS LINE)
    obj.saveRegionalPowerSummaryToExcel(outputFile);

            % 5. Data Quality & Sleep Statistics
            obj.saveAdditionalSheets(outputFile);
            
            fprintf('SUCCESS: Excel file created with sleep-focused analysis: %s\n', outputFile);
        end

        function saveSleepPeriodAnalysisToExcel(obj, outputFile)
            fprintf('  Saving sleep period analysis...\n');
            
            % SPT Analysis
            sptTable = obj.createSPTAnalysisTable();
            writetable(sptTable, outputFile, 'Sheet', 'SPT_Analysis');
            
            % TST Analysis
            tstTable = obj.createTSTAnalysisTable();
            writetable(tstTable, outputFile, 'Sheet', 'TST_Analysis');
            

        end

        function saveStageAnalysisToExcel(obj, outputFile)
            if ~isempty(obj.numericHypnogram)
                fprintf('  Saving stage-specific analysis...\n');
                
                % Stage analysis includes: N1, N2, N3, REM, WASO (NO general wake)
                stageTable = obj.createStageAnalysisTable();
                writetable(stageTable, outputFile, 'Sheet', 'Stage_Specific_Analysis');
            end
        end

        function saveCycleAnalysisToExcel(obj, outputFile)
            if ~isempty(obj.sleepCycles)
                fprintf('  Saving sleep cycle analysis...\n');
                
                cycleTable = obj.createCycleAnalysisTable();
                writetable(cycleTable, outputFile, 'Sheet', 'Sleep_Cycle_Analysis');
            end
        end

        function sptTable = createSPTAnalysisTable(obj)
            % Create table for SPT (Sleep Period Time) analysis
            channels = obj.spectralResults.channels;
            
            sptTable = table();
            sptTable.Channel = channels';
            
            bands = {'Delta', 'Theta', 'Alpha', 'Sigma', 'Beta', 'Gamma'};
            
            % Absolute Power
            for b = 1:length(bands)
                bandName = bands{b};
                powerData = zeros(length(channels), 1);
                
                for ch = 1:length(channels)
                    sanitizedName = obj.sanitizeFieldName(channels{ch});
                    if isfield(obj.spectralResults.bandPower, sanitizedName) && ...
                       isfield(obj.spectralResults.bandPower.(sanitizedName), 'SPT') && ...
                       isfield(obj.spectralResults.bandPower.(sanitizedName).SPT, bandName)
                        powerData(ch) = obj.spectralResults.bandPower.(sanitizedName).SPT.(bandName);
                    else
                        powerData(ch) = NaN;
                    end
                end
                sptTable.(['SPT_' bandName '_uV2']) = powerData;
            end
            
            % Relative Power (%)
            for b = 1:length(bands)
                bandName = bands{b};
                relPowerData = zeros(length(channels), 1);
                
                for ch = 1:length(channels)
                    sanitizedName = obj.sanitizeFieldName(channels{ch});
                    if isfield(obj.spectralResults.relativePower, sanitizedName) && ...
                       isfield(obj.spectralResults.relativePower.(sanitizedName), 'SPT') && ...
                       isfield(obj.spectralResults.relativePower.(sanitizedName).SPT, bandName)
                        relPowerData(ch) = obj.spectralResults.relativePower.(sanitizedName).SPT.(bandName) * 100;
                    else
                        relPowerData(ch) = NaN;
                    end
                end
                sptTable.(['SPT_' bandName '_pct']) = relPowerData;
            end
            
            % Spectral Ratios
            ratioNames = {'theta_beta', 'delta_theta', 'alpha_theta', 'sigma_delta'};
            for r = 1:length(ratioNames)
                ratioName = ratioNames{r};
                ratioData = zeros(length(channels), 1);
                
                for ch = 1:length(channels)
                    sanitizedName = obj.sanitizeFieldName(channels{ch});
                    if isfield(obj.spectralResults.bandPower, sanitizedName) && ...
                       isfield(obj.spectralResults.bandPower.(sanitizedName), 'SPT') && ...
                       isfield(obj.spectralResults.bandPower.(sanitizedName).SPT, 'ratios') && ...
                       isfield(obj.spectralResults.bandPower.(sanitizedName).SPT.ratios, ratioName)
                        ratioData(ch) = obj.spectralResults.bandPower.(sanitizedName).SPT.ratios.(ratioName);
                    else
                        ratioData(ch) = NaN;
                    end
                end
                sptTable.(['SPT_' ratioName '_ratio']) = ratioData;
            end
        end

        function tstTable = createTSTAnalysisTable(obj)
            % Create table for TST (Total Sleep Time) analysis
            channels = obj.spectralResults.channels;
            
            tstTable = table();
            tstTable.Channel = channels';
            
            bands = {'Delta', 'Theta', 'Alpha', 'Sigma', 'Beta', 'Gamma'};
            
            % Absolute Power
            for b = 1:length(bands)
                bandName = bands{b};
                powerData = zeros(length(channels), 1);
                
                for ch = 1:length(channels)
                    sanitizedName = obj.sanitizeFieldName(channels{ch});
                    if isfield(obj.spectralResults.bandPower, sanitizedName) && ...
                       isfield(obj.spectralResults.bandPower.(sanitizedName), 'TST') && ...
                       isfield(obj.spectralResults.bandPower.(sanitizedName).TST, bandName)
                        powerData(ch) = obj.spectralResults.bandPower.(sanitizedName).TST.(bandName);
                    else
                        powerData(ch) = NaN;
                    end
                end
                tstTable.(['TST_' bandName '_uV2']) = powerData;
            end
            
            % Relative Power (%)
            for b = 1:length(bands)
                bandName = bands{b};
                relPowerData = zeros(length(channels), 1);
                
                for ch = 1:length(channels)
                    sanitizedName = obj.sanitizeFieldName(channels{ch});
                    if isfield(obj.spectralResults.relativePower, sanitizedName) && ...
                       isfield(obj.spectralResults.relativePower.(sanitizedName), 'TST') && ...
                       isfield(obj.spectralResults.relativePower.(sanitizedName).TST, bandName)
                        relPowerData(ch) = obj.spectralResults.relativePower.(sanitizedName).TST.(bandName) * 100;
                    else
                        relPowerData(ch) = NaN;
                    end
                end
                tstTable.(['TST_' bandName '_pct']) = relPowerData;
            end
        end

        function wasoTable = createWASOAnalysisTable(obj)
            % Create table for WASO (Wake After Sleep Onset) analysis
            channels = obj.spectralResults.channels;
            
            wasoTable = table();
            wasoTable.Channel = channels';
            
            bands = {'Delta', 'Theta', 'Alpha', 'Sigma', 'Beta', 'Gamma'};
            
            % Absolute Power
            for b = 1:length(bands)
                bandName = bands{b};
                powerData = zeros(length(channels), 1);
                
                for ch = 1:length(channels)
                    sanitizedName = obj.sanitizeFieldName(channels{ch});
                    if isfield(obj.spectralResults.bandPower, sanitizedName) && ...
                       isfield(obj.spectralResults.bandPower.(sanitizedName), 'WASO') && ...
                       isfield(obj.spectralResults.bandPower.(sanitizedName).WASO, bandName)
                        powerData(ch) = obj.spectralResults.bandPower.(sanitizedName).WASO.(bandName);
                    else
                        powerData(ch) = NaN;
                    end
                end
                wasoTable.(['WASO_' bandName '_uV2']) = powerData;
            end
            
            % Relative Power (%)
            for b = 1:length(bands)
                bandName = bands{b};
                relPowerData = zeros(length(channels), 1);
                
                for ch = 1:length(channels)
                    sanitizedName = obj.sanitizeFieldName(channels{ch});
                    if isfield(obj.spectralResults.relativePower, sanitizedName) && ...
                       isfield(obj.spectralResults.relativePower.(sanitizedName), 'WASO') && ...
                       isfield(obj.spectralResults.relativePower.(sanitizedName).WASO, bandName)
                        relPowerData(ch) = obj.spectralResults.relativePower.(sanitizedName).WASO.(bandName) * 100;
                    else
                        relPowerData(ch) = NaN;
                    end
                end
                wasoTable.(['WASO_' bandName '_pct']) = relPowerData;
            end
        end

        function stageTable = createStageAnalysisTable(obj)
            % Create table for stage-specific analysis (N1, N2, N3, REM, WASO only - NO general wake)
            channels = obj.spectralResults.channels;
            stages = {'N1', 'N2', 'N3', 'REM', 'WASO'}; % NO 'W' (general wake)
            bands = {'Delta', 'Theta', 'Alpha', 'Sigma', 'Beta', 'Gamma'};
            
            % Initialize table
            stageTable = table();
            stageTable.Channel = repmat(channels', length(stages), 1);
            stageTable.SleepStage = repelem(stages, length(channels))';
            
            % Initialize all power columns with NaN
            for b = 1:length(bands)
                bandName = bands{b};
                stageTable.(['Power_' bandName '_uV2']) = NaN(height(stageTable), 1);
                stageTable.(['Power_' bandName '_pct']) = NaN(height(stageTable), 1);
            end
            
            % Fill in the data
            for ch = 1:length(channels)
                sanitizedName = obj.sanitizeFieldName(channels{ch});
                
                for s = 1:length(stages)
                    stage = stages{s};
                    rowIdx = (s-1) * length(channels) + ch;
                    
                    % Check if stage data exists
                    if isfield(obj.spectralResults.bandPower, sanitizedName) && ...
                       isfield(obj.spectralResults.bandPower.(sanitizedName), stage)
                        
                        stagePower = obj.spectralResults.bandPower.(sanitizedName).(stage);
                        
                        % Fill absolute power
                        for b = 1:length(bands)
                            bandName = bands{b};
                            if isfield(stagePower, bandName)
                                stageTable.(['Power_' bandName '_uV2'])(rowIdx) = stagePower.(bandName);
                            end
                        end
                        
                        % Fill relative power
                        if isfield(obj.spectralResults.relativePower, sanitizedName) && ...
                           isfield(obj.spectralResults.relativePower.(sanitizedName), 'stages') && ...
                           isfield(obj.spectralResults.relativePower.(sanitizedName).stages, stage)
                            
                            stageRelPower = obj.spectralResults.relativePower.(sanitizedName).stages.(stage);
                            
                            for b = 1:length(bands)
                                bandName = bands{b};
                                if isfield(stageRelPower, bandName)
                                    stageTable.(['Power_' bandName '_pct'])(rowIdx) = stageRelPower.(bandName) * 100;
                                end
                            end
                        end
                    end
                end
            end
        end

        function cycleTable = createCycleAnalysisTable(obj)
            % Create table for sleep cycle analysis
            channels = obj.spectralResults.channels;
            
            % Get all cycles across all channels
            allCycles = {};
            for ch = 1:length(channels)
                sanitizedName = obj.sanitizeFieldName(channels{ch});
                if isfield(obj.spectralResults.sleepCycles, sanitizedName)
                    cycleFields = fieldnames(obj.spectralResults.sleepCycles.(sanitizedName));
                    allCycles = union(allCycles, cycleFields);
                end
            end
            
            if isempty(allCycles)
                cycleTable = table();
                return;
            end
            
            bands = {'Delta', 'Theta', 'Alpha', 'Sigma', 'Beta', 'Gamma'};
            
            % Initialize table
            cycleTable = table();
            
            % Create rows for each channel and cycle combination
            rowCount = 0;
            for ch = 1:length(channels)
                for c = 1:length(allCycles)
                    rowCount = rowCount + 1;
                end
            end
            
            % Initialize table arrays
            cycleTable.Channel = cell(rowCount, 1);
            cycleTable.Cycle = cell(rowCount, 1);
            cycleTable.StartEpoch = NaN(rowCount, 1);
            cycleTable.EndEpoch = NaN(rowCount, 1);
            cycleTable.Duration_min = NaN(rowCount, 1);
            
            for b = 1:length(bands)
                bandName = bands{b};
                cycleTable.(['Power_' bandName '_uV2']) = NaN(rowCount, 1);
                cycleTable.(['Power_' bandName '_pct']) = NaN(rowCount, 1);
            end
            
            % Fill the table
            rowIdx = 1;
            for ch = 1:length(channels)
                channelName = channels{ch};
                sanitizedName = obj.sanitizeFieldName(channelName);
                
                for c = 1:length(allCycles)
                    cycleName = allCycles{c};
                    
                    cycleTable.Channel{rowIdx} = channelName;
                    cycleTable.Cycle{rowIdx} = cycleName;
                    
                    if isfield(obj.spectralResults.sleepCycles, sanitizedName) && ...
                       isfield(obj.spectralResults.sleepCycles.(sanitizedName), cycleName)
                        
                        cycleData = obj.spectralResults.sleepCycles.(sanitizedName).(cycleName);
                        
                        cycleTable.StartEpoch(rowIdx) = cycleData.startEpoch;
                        cycleTable.EndEpoch(rowIdx) = cycleData.endEpoch;
                        cycleTable.Duration_min(rowIdx) = cycleData.duration_minutes;
                        
                        % Fill power data
                        for b = 1:length(bands)
                            bandName = bands{b};
                            if isfield(cycleData.bandPower, bandName)
                                cycleTable.(['Power_' bandName '_uV2'])(rowIdx) = cycleData.bandPower.(bandName);
                            end
                            if isfield(cycleData.relativePower, bandName)
                                cycleTable.(['Power_' bandName '_pct'])(rowIdx) = cycleData.relativePower.(bandName) * 100;
                            end
                        end
                    end
                    
                    rowIdx = rowIdx + 1;
                end
            end
        end
       
        function powerValue = getRegionalPowerValue(obj, sanitizedName, period, bandName)
    % Helper method to get power value for different periods and bands
    
    powerValue = NaN;
    
    try
        if strcmp(period, 'TST')
            % TST power
            if isfield(obj.spectralResults.bandPower, sanitizedName) && ...
               isfield(obj.spectralResults.bandPower.(sanitizedName), 'TST')
                
                if strcmp(bandName, 'total')
                    % Total power
                    if isfield(obj.spectralResults.bandPower.(sanitizedName).TST, 'totalPower')
                        powerValue = obj.spectralResults.bandPower.(sanitizedName).TST.totalPower;
                    end
                else
                    % Band power
                    if isfield(obj.spectralResults.bandPower.(sanitizedName).TST, bandName)
                        powerValue = obj.spectralResults.bandPower.(sanitizedName).TST.(bandName);
                    end
                end
            end
            
        elseif strcmp(period, 'NREM')
            % NREM average power (N2 + N3)
            nremPower = 0;
            nremBands = 0;
            
            % N2 power
            if isfield(obj.spectralResults.bandPower, sanitizedName) && ...
               isfield(obj.spectralResults.bandPower.(sanitizedName), 'N2')
                
                if strcmp(bandName, 'total')
                    if isfield(obj.spectralResults.bandPower.(sanitizedName).N2, 'totalPower')
                        n2Power = obj.spectralResults.bandPower.(sanitizedName).N2.totalPower;
                        if n2Power > 0
                            nremPower = nremPower + n2Power;
                            nremBands = nremBands + 1;
                        end
                    end
                else
                    if isfield(obj.spectralResults.bandPower.(sanitizedName).N2, bandName)
                        n2Power = obj.spectralResults.bandPower.(sanitizedName).N2.(bandName);
                        if n2Power > 0
                            nremPower = nremPower + n2Power;
                            nremBands = nremBands + 1;
                        end
                    end
                end
            end
            
            % N3 power
            if isfield(obj.spectralResults.bandPower, sanitizedName) && ...
               isfield(obj.spectralResults.bandPower.(sanitizedName), 'N3')
                
                if strcmp(bandName, 'total')
                    if isfield(obj.spectralResults.bandPower.(sanitizedName).N3, 'totalPower')
                        n3Power = obj.spectralResults.bandPower.(sanitizedName).N3.totalPower;
                        if n3Power > 0
                            nremPower = nremPower + n3Power;
                            nremBands = nremBands + 1;
                        end
                    end
                else
                    if isfield(obj.spectralResults.bandPower.(sanitizedName).N3, bandName)
                        n3Power = obj.spectralResults.bandPower.(sanitizedName).N3.(bandName);
                        if n3Power > 0
                            nremPower = nremPower + n3Power;
                            nremBands = nremBands + 1;
                        end
                    end
                end
            end
            
            if nremBands > 0
                powerValue = nremPower / nremBands;
            end
            
        elseif strcmp(period, 'REM')
            % REM power
            if isfield(obj.spectralResults.bandPower, sanitizedName) && ...
               isfield(obj.spectralResults.bandPower.(sanitizedName), 'REM')
                
                if strcmp(bandName, 'total')
                    if isfield(obj.spectralResults.bandPower.(sanitizedName).REM, 'totalPower')
                        powerValue = obj.spectralResults.bandPower.(sanitizedName).REM.totalPower;
                    end
                else
                    if isfield(obj.spectralResults.bandPower.(sanitizedName).REM, bandName)
                        powerValue = obj.spectralResults.bandPower.(sanitizedName).REM.(bandName);
                    end
                end
            end
        end
    catch
        powerValue = NaN;
    end
end
        
        function regionalPowerTable = createRegionalPowerDBTable(obj)
    % Create regional summary table with total power AND band power in dB for TST, NREM, REM
    
    channels = obj.spectralResults.channels;
    
    % Define channel groups by region
    frontalChannels = {};
    centralChannels = {};
    occipitalChannels = {};
    
    for i = 1:length(channels)
        chName = channels{i};
        if contains(chName, 'F3') || contains(chName, 'F4') || contains(chName, 'Fz') || contains(chName, 'Fp')
            frontalChannels{end+1} = chName;
        elseif contains(chName, 'C3') || contains(chName, 'C4') || contains(chName, 'Cz')
            centralChannels{end+1} = chName;
        elseif contains(chName, 'O1') || contains(chName, 'O2') || contains(chName, 'Oz')
            occipitalChannels{end+1} = chName;
        end
    end
    
    % Define regions
    regions = {
        'Global', channels;
        'Frontal', frontalChannels;
        'Central', centralChannels; 
        'Occipital', occipitalChannels
        };
    
    % Define sleep periods and frequency bands
    sleepPeriods = {'TST', 'NREM', 'REM'};
    freqBands = {
        'Delta',    [0.5, 4.0];
        'Theta',    [4.0, 8.0];
        'Alpha',    [8.0, 12.0];
        'Sigma',    [12.0, 15.0];
        'Beta',     [15.0, 30.0];
        'Gamma',    [30.0, 45.0]
        };
    
    % Initialize table
    regionalPowerTable = table();
    regionalPowerTable.Region = regions(:,1);
    regionalPowerTable.Channel_Count = cellfun(@length, regions(:,2));
    
    % Calculate TOTAL POWER for each region and sleep period
    for p = 1:length(sleepPeriods)
        period = sleepPeriods{p};
        totalPowerData = zeros(size(regions, 1), 1);
        
        for r = 1:size(regions, 1)
            region = regions{r, 1};
            regionChannels = regions{r, 2};
            
            if isempty(regionChannels)
                totalPowerData(r) = NaN;
                continue;
            end
            
            regionPowerSum = 0;
            validChannels = 0;
            
            for ch = 1:length(regionChannels)
                channelName = regionChannels{ch};
                sanitizedName = obj.sanitizeFieldName(channelName);
                
                powerValue = obj.getRegionalPowerValue(sanitizedName, period, 'total');
                if ~isnan(powerValue) && powerValue > 0
                    regionPowerSum = regionPowerSum + powerValue;
                    validChannels = validChannels + 1;
                end
            end
            
            % Calculate average power for the region and convert to dB
            if validChannels > 0
                avgRegionPower = regionPowerSum / validChannels;
                % Convert to dB with proper reference (1 μV²)
                totalPowerData(r) = 10 * log10(avgRegionPower);
            else
                totalPowerData(r) = NaN;
            end
        end
        
        % Add total power to table
        regionalPowerTable.([period '_TotalPower_dB']) = totalPowerData;
    end
    
    % Calculate BAND POWER for each region, sleep period, and frequency band
    for p = 1:length(sleepPeriods)
        period = sleepPeriods{p};
        
        for b = 1:size(freqBands, 1)
            bandName = freqBands{b, 1};
            bandPowerData = zeros(size(regions, 1), 1);
            
            for r = 1:size(regions, 1)
                region = regions{r, 1};
                regionChannels = regions{r, 2};
                
                if isempty(regionChannels)
                    bandPowerData(r) = NaN;
                    continue;
                end
                
                regionBandPowerSum = 0;
                validChannels = 0;
                
                for ch = 1:length(regionChannels)
                    channelName = regionChannels{ch};
                    sanitizedName = obj.sanitizeFieldName(channelName);
                    
                    powerValue = obj.getRegionalPowerValue(sanitizedName, period, bandName);
                    if ~isnan(powerValue) && powerValue > 0
                        regionBandPowerSum = regionBandPowerSum + powerValue;
                        validChannels = validChannels + 1;
                    end
                end
                
                % Calculate average band power for the region and convert to dB
                if validChannels > 0
                    avgRegionBandPower = regionBandPowerSum / validChannels;
                    % Convert to dB with proper reference (1 μV²)
                    bandPowerData(r) = 10 * log10(avgRegionBandPower);
                else
                    bandPowerData(r) = NaN;
                end
            end
            
            % Add band power to table
            regionalPowerTable.([period '_' bandName '_dB']) = bandPowerData;
        end
    end
    
    % Add channel lists for reference
    regionalPowerTable.Channels = cell(size(regions, 1), 1);
    for r = 1:size(regions, 1)
        regionalPowerTable.Channels{r} = strjoin(regions{r, 2}, ', ');
    end
end
        function saveRegionalPowerSummaryToExcel(obj, outputFile)
    fprintf('  Saving regional power summary...\n');
    
    regionalTable = obj.createRegionalPowerDBTable();
    writetable(regionalTable, outputFile, 'Sheet', 'Regional_Power_Summary');
end
    end
    
    methods (Access = private)
        
        function loadHypnogram(obj)
            % Load hypnogram from XML file
            try
                if isempty(obj.xmlPath) || ~exist(obj.xmlPath, 'file')
                    fprintf('No XML file provided for hypnogram.\n');
                    obj.numericHypnogram = [];
                    return;
                end

                fprintf('Loading hypnogram: %s\n', obj.xmlPath);

                % Use the same approach as MicrostateAnalysisClass
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
                obj.numericHypnogram = [];
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

            % Store the MAPPED names, not the raw names
            obj.mappedChannelNames = ChannelMappingHelper(rawChannelNames);
            
            % Use mapped names for channel selection
            obj.channelLabels = obj.mappedChannelNames;

            % Load all data - keep in cell array format
            obj.data = obj.loadEDFData(1:length(rawChannelNames));

            % Get sampling rates for ALL channels
            obj.fs = obj.getSamplingRates();

            fprintf('All available channels (MAPPED): %s\n', strjoin(obj.channelLabels, ', '));
            fprintf('Sampling rates: %s Hz\n', mat2str(obj.fs));
            fprintf('Data size: %d channels\n', length(obj.data));
            
            % Store all channel data for cleaning - use mapped names
            obj.allChannelData = obj.data;
            obj.allChannelLabels = obj.mappedChannelNames;
        end
        
        function data = loadEDFData(obj, channelIndices)
            % Load data from EDF file
            fprintf('Loading data for %d channels...\n', length(channelIndices));

            try
                % Use signalCell directly
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
            % Returns array of sampling rates for each channel
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

                % Use sleep_cycles function - CORRECTED CALL
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
                fprintf('Make sure sleep_cycles.m is in your MATLAB path\n');
                obj.sleepCycles = [];
            end
        end
        
        function [cleanData, artifactInfo] = performTargetedCleaning(obj, eegChannelIndices, eegChannelNames)
            % Targeted cleaning for EEG channels
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

            % Use first channel's sampling rate for cleaning
            cleaning_fs = obj.fs(1);

            [cleanData, artifactInfo] = obj.artifactDetector.fullDataCleaning(...
                dataToClean, labelsToClean, cleaning_fs, obj.numericHypnogram);

            % Store global artifact mask for sleep statistics
            if isfield(artifactInfo, 'globalArtifactMask')
                obj.globalArtifactMask = artifactInfo.globalArtifactMask;
            else
                % Create a default artifact mask if not provided
                fprintf('Warning: globalArtifactMask not found in artifactInfo, creating default mask\n');
                obj.globalArtifactMask = false(1, length(dataToClean{1}));
            end

            % Extract only the EEG channels (exclude ECG channel from results)
            cleanData = cleanData(1:length(eegChannelIndices));
        end
        
        function [bandPower, totalPower] = calculateBandPower(obj, psd_dB, frequencies, freqBands)
    % Calculate absolute band power and total power from PSD in dB
    % CORRECTED: Use sleep-relevant frequency range 0.5-45 Hz
    
    bandPower = struct();
    totalPower = 0;
    
    % Convert PSD from dB to linear power first
    psd_linear = 10.^(psd_dB / 10);  % Convert dB to linear power (μV²/Hz)
    
    % CORRECTED: Total power should be across 0.5-45 Hz (not 0.5-45)
    totalMask = frequencies >= 0.5 & frequencies <= 45;
    if any(totalMask)
        totalPSD_linear = psd_linear(totalMask);
        totalPSD_linear = totalPSD_linear(isfinite(totalPSD_linear));
        if ~isempty(totalPSD_linear)
            % Integrate PSD over frequency to get total power
            freq_resolution = frequencies(2) - frequencies(1); % Hz per bin
            totalPower = sum(totalPSD_linear) * freq_resolution; % μV²
        end
    end
    
    % Calculate absolute power for each frequency band
    for i = 1:size(freqBands, 1)
        bandName = freqBands{i, 1};
        bandRange = freqBands{i, 2};
        
        % Use inclusive boundaries for sleep bands
        bandMask = frequencies >= bandRange(1) & frequencies <= bandRange(2);
        
        if any(bandMask)
            bandPSD_linear = psd_linear(bandMask);
            bandPSD_linear = bandPSD_linear(isfinite(bandPSD_linear));
            if ~isempty(bandPSD_linear)
                % Integrate PSD over frequency band to get absolute power
                freq_resolution = frequencies(2) - frequencies(1); % Hz per bin
                bandPower.(bandName) = sum(bandPSD_linear) * freq_resolution; % μV²
            else
                bandPower.(bandName) = 0;
            end
        else
            bandPower.(bandName) = 0;
        end
    end
    
    % Store total power for reference
    bandPower.totalPower = totalPower;
end

        function [psd_dB, frequencies] = calculateAdvancedPSD(obj, data, fs)
    % Calculate Power Spectral Density using Welch's method
    % CORRECTED: Focus on sleep-relevant frequencies 0.5-45 Hz
    
    fprintf('Calculating PSD using Welch method (0.5-45 Hz)...\n');
    
    % Parameters for PSD calculation
    windowLength = min(4 * fs, length(data)); % 4-second windows
    overlap = 0.5; % 50% overlap
    nfft = max(1024, 2^nextpow2(windowLength));
    
    % Remove any remaining NaN values
    data = fillmissing(data, 'linear');
    
    % Calculate PSD using pwelch (returns PSD in (μV²/Hz))
    [psd_linear, frequencies] = pwelch(data, hamming(windowLength), ...
        round(overlap * windowLength), nfft, fs);
    
    % CORRECTED: Filter to sleep-relevant frequencies only (0.5-45 Hz)
    freqMask = frequencies >= 0.5 & frequencies <= 45;
    frequencies = frequencies(freqMask);
    psd_linear = psd_linear(freqMask);
    
    % Convert to dB (10*log10(μV²/Hz))
    psd_dB = 10 * log10(psd_linear);
    
    fprintf('PSD calculated: %d frequency bins from %.1f to %.1f Hz\n', ...
        length(frequencies), frequencies(1), frequencies(end));
    fprintf('  Frequency resolution: %.3f Hz/bin\n', frequencies(2) - frequencies(1));
end
        
        function relativePower = calculateRelativePower(obj, bandPower, totalPower, freqBands)
            % Calculate relative power (% of total power)
            relativePower = struct();
            
            if totalPower > 0
                for i = 1:size(freqBands, 1)
                    bandName = freqBands{i, 1};
                    if isfield(bandPower, bandName)
                        relativePower.(bandName) = bandPower.(bandName) / totalPower;
                    else
                        relativePower.(bandName) = 0;
                    end
                end
            else
                % If total power is zero, set all relative powers to zero
                for i = 1:size(freqBands, 1)
                    bandName = freqBands{i, 1};
                    relativePower.(bandName) = 0;
                end
            end
        end
        
        function calculateAdvancedMetrics(obj, freqBands)
            % Calculate spectral ratios and store in bandPower structure
            fprintf('Calculating advanced spectral metrics...\n');
            
            for ch = 1:length(obj.spectralResults.channels)
                channelName = obj.spectralResults.channels{ch};
                sanitizedName = obj.sanitizeFieldName(channelName);
                
                if isfield(obj.spectralResults.bandPower, sanitizedName)
                    bandPower = obj.spectralResults.bandPower.(sanitizedName);
                    
                    % Calculate spectral ratios for each sleep period
                    periods = {'SPT', 'TST', 'WASO'};
                    for p = 1:length(periods)
                        period = periods{p};
                        if isfield(bandPower, period)
                            periodPower = bandPower.(period);
                            ratios = struct();
                            
                            % Theta/Beta ratio
                            if isfield(periodPower, 'Theta') && isfield(periodPower, 'Beta') && periodPower.Beta > 0
                                ratios.theta_beta = periodPower.Theta / periodPower.Beta;
                            else
                                ratios.theta_beta = NaN;
                            end
                            
                            % Delta/Theta ratio
                            if isfield(periodPower, 'Delta') && isfield(periodPower, 'Theta') && periodPower.Theta > 0
                                ratios.delta_theta = periodPower.Delta / periodPower.Theta;
                            else
                                ratios.delta_theta = NaN;
                            end
                            
                            % Alpha/Theta ratio
                            if isfield(periodPower, 'Alpha') && isfield(periodPower, 'Theta') && periodPower.Theta > 0
                                ratios.alpha_theta = periodPower.Alpha / periodPower.Theta;
                            else
                                ratios.alpha_theta = NaN;
                            end
                            
                            % Sigma/Delta ratio
                            if isfield(periodPower, 'Sigma') && isfield(periodPower, 'Delta') && periodPower.Delta > 0
                                ratios.sigma_delta = periodPower.Sigma / periodPower.Delta;
                            else
                                ratios.sigma_delta = NaN;
                            end
                            
                            % Store ratios
                            obj.spectralResults.bandPower.(sanitizedName).(period).ratios = ratios;
                        end
                    end
                end
            end
        end

        function printSummaryStatistics(obj)
            % Enhanced summary focused on sleep periods
            if isempty(obj.spectralResults)
                return;
            end
            
            fprintf('\n=== SLEEP PERIOD SPECTRAL ANALYSIS SUMMARY ===\n');
            fprintf('Channels analyzed: %s\n', strjoin(obj.spectralResults.channels, ', '));
            
            % Print cleaning summary
            if ~isempty(obj.cleaningSummary)
                fprintf('Data quality: %.1f%% clean data\n', obj.cleaningSummary.cleanDataPercentage);
                fprintf('Artifact contamination: %.1f%%\n', obj.cleaningSummary.artifactPercentage);
            end
            
            % Print sleep period metrics for first channel as example
            if ~isempty(obj.spectralResults.channels)
                firstChannel = obj.spectralResults.channels{1};
                sanitizedName = obj.sanitizeFieldName(firstChannel);
                
                if isfield(obj.spectralResults.bandPower, sanitizedName)
                    fprintf('\n=== SLEEP PERIOD METRICS FOR %s ===\n', firstChannel);
                    
                    periods = {'SPT', 'TST', 'WASO'};
                    for p = 1:length(periods)
                        period = periods{p};
                        if isfield(obj.spectralResults.bandPower.(sanitizedName), period)
                            bandPower = obj.spectralResults.bandPower.(sanitizedName).(period);
                            relPower = obj.spectralResults.relativePower.(sanitizedName).(period);
                            
                            fprintf('\n%s POWER:\n', period);
                            if isfield(bandPower, 'Delta')
                                fprintf('  Delta:   %.3f μV² (%.1f%%)\n', bandPower.Delta, relPower.Delta * 100);
                            end
                            if isfield(bandPower, 'Theta')
                                fprintf('  Theta:   %.3f μV² (%.1f%%)\n', bandPower.Theta, relPower.Theta * 100);
                            end
                            if isfield(bandPower, 'Alpha')
                                fprintf('  Alpha:   %.3f μV² (%.1f%%)\n', bandPower.Alpha, relPower.Alpha * 100);
                            end
                            if isfield(bandPower, 'Sigma')
                                fprintf('  Sigma:   %.3f μV² (%.1f%%)\n', bandPower.Sigma, relPower.Sigma * 100);
                            end
                            if isfield(bandPower, 'Beta')
                                fprintf('  Beta:    %.3f μV² (%.1f%%)\n', bandPower.Beta, relPower.Beta * 100);
                            end
                            if isfield(bandPower, 'Gamma')
                                fprintf('  Gamma:   %.3f μV² (%.1f%%)\n', bandPower.Gamma, relPower.Gamma * 100);
                            end
                        end
                    end
                end
            end
        end

        function [tstBandPower, sptBandPower, wasoBandPower, tstTotalPower, sptTotalPower, wasoTotalPower] = calculateSleepAnalysis(obj, channelData, channelName, fs, freqBands)
            % Calculate SPT, TST, and WASO analysis with relative power
            if isempty(obj.numericHypnogram)
                tstBandPower = [];
                sptBandPower = [];
                wasoBandPower = [];
                tstTotalPower = 0;
                sptTotalPower = 0;
                wasoTotalPower = 0;
                return;
            end
            
            fprintf('  Calculating SPT, TST, and WASO analysis for %s\n', channelName);
            
            % Create masks for each sleep period
            tstMask = obj.createTSTMask(length(channelData));      % Sleep only
            sptMask = obj.createSPTMask(length(channelData));      % SPT (TST + WASO)
            wasoMask = obj.createWASOMask(length(channelData));    % WASO only
            
            % TST Analysis (Sleep only)
            if sum(tstMask) > 30 * fs % At least 30 seconds of sleep data
                tstData = channelData(tstMask);
                [tstPSD, frequencies] = obj.calculateAdvancedPSD(tstData, fs);
                [tstBandPower, tstTotalPower] = obj.calculateBandPower(tstPSD, frequencies, freqBands);
            else
                tstBandPower = [];
                tstTotalPower = 0;
            end
            
            % SPT Analysis (Sleep + WASO within sleep period)
            if sum(sptMask) > 30 * fs % At least 30 seconds of SPT data
                sptData = channelData(sptMask);
                [sptPSD, frequencies] = obj.calculateAdvancedPSD(sptData, fs);
                [sptBandPower, sptTotalPower] = obj.calculateBandPower(sptPSD, frequencies, freqBands);
            else
                sptBandPower = [];
                sptTotalPower = 0;
            end
            
            % WASO Analysis (Wake within SPT only)
            if sum(wasoMask) > 30 * fs % At least 30 seconds of WASO data
                wasoData = channelData(wasoMask);
                [wasoPSD, frequencies] = obj.calculateAdvancedPSD(wasoData, fs);
                [wasoBandPower, wasoTotalPower] = obj.calculateBandPower(wasoPSD, frequencies, freqBands);
            else
                wasoBandPower = [];
                wasoTotalPower = 0;
            end
        end

        function sptMask = createSPTMask(obj, totalSamples)
            % Create mask for Sleep Period Time (SPT) - includes WASO within sleep period
            if isempty(obj.numericHypnogram)
                sptMask = false(1, totalSamples);
                return;
            end

            fs_ref = obj.fs(1);
            samplesPerEpoch = 30 * fs_ref;
            sptMask = false(1, totalSamples);

            % Find Sleep Period Time boundaries
            % SPT = First sleep epoch to last sleep epoch (including intervening wake/WASO)
            sleepEpochs = find(obj.numericHypnogram >= 1 & obj.numericHypnogram <= 5);
            
            if isempty(sleepEpochs)
                fprintf('  No sleep epochs found for SPT calculation\n');
                return;
            end
            
            sptStart = min(sleepEpochs);
            sptEnd = max(sleepEpochs);
            
            % Create mask for entire SPT period
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
            % Create mask for Total Sleep Time (TST) - sleep stages only (excludes all wake)
            if isempty(obj.numericHypnogram)
                tstMask = false(1, totalSamples);
                return;
            end

            fs_ref = obj.fs(1);
            samplesPerEpoch = 30 * fs_ref;
            tstMask = false(1, totalSamples);

            for epoch = 1:min(length(obj.numericHypnogram), ceil(totalSamples/samplesPerEpoch))
                % Only include actual sleep stages (exclude wake stage 0)
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
            % Create mask for Wake After Sleep Onset (WASO) - wake within SPT only
            if isempty(obj.numericHypnogram)
                wasoMask = false(1, totalSamples);
                return;
            end

            fs_ref = obj.fs(1);
            samplesPerEpoch = 30 * fs_ref;
            wasoMask = false(1, totalSamples);

            % Find SPT boundaries first
            sleepEpochs = find(obj.numericHypnogram >= 1 & obj.numericHypnogram <= 5);
            
            if isempty(sleepEpochs)
                fprintf('  No sleep epochs found for WASO calculation\n');
                return;
            end
            
            sptStart = min(sleepEpochs);
            sptEnd = max(sleepEpochs);
            
            % Create mask for wake epochs within SPT only
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

        function stageName = getStageName(~, stageNum)
            % Convert numeric stage to name
            switch stageNum
                case 0, stageName = 'W';
                case 1, stageName = 'N1';
                case 2, stageName = 'N2';
                case 3, stageName = 'N3';
                case 4, stageName = 'N3';
                case 5, stageName = 'REM';
                otherwise, stageName = sprintf('Stage_%d', stageNum);
            end
        end

        function safeName = sanitizeFieldName(~, originalName)
            % Simple field name sanitization
            safeName = regexprep(originalName, '[^a-zA-Z0-9_]', '_');
            
            if ~isempty(safeName) && ~isletter(safeName(1))
                safeName = ['Channel_', safeName];
            end
            
            if isempty(safeName)
                safeName = 'UnknownChannel';
            end
        end

        function calculateStageSpecificPSD(obj, channelData, channelName, fs, freqBands)
    % Enhanced stage-specific analysis with relative power
    % ONLY includes sleep stages + WASO, NOT general wake
    if isempty(obj.numericHypnogram)
        fprintf('  No hypnogram available for stage-specific analysis\n');
        return;
    end
    
    samplesPerEpoch = 30 * fs;
    numCompleteEpochs = min(floor(length(channelData) / samplesPerEpoch), length(obj.numericHypnogram));
    
    % Initialize stage masks if not already done
    if isempty(obj.stageMasks)
        obj.initializeStageMasks(numCompleteEpochs);
    end
    
    % Only include sleep stages + WASO, NOT general wake
    stages = {'N1', 'N2', 'N3', 'REM', 'WASO'}; % NO 'W'
    
    sanitizedName = obj.sanitizeFieldName(channelName);
    
    % Initialize structures in the CORRECT location (bandPower, not sleepStages)
    if ~isfield(obj.spectralResults.bandPower, sanitizedName)
        obj.spectralResults.bandPower.(sanitizedName) = struct();
    end
    if ~isfield(obj.spectralResults.relativePower, sanitizedName)
        obj.spectralResults.relativePower.(sanitizedName) = struct();
    end
    if ~isfield(obj.spectralResults.relativePower.(sanitizedName), 'stages')
        obj.spectralResults.relativePower.(sanitizedName).stages = struct();
    end
    
    fprintf('  Stage-specific analysis for %s (%d epochs)\n', channelName, numCompleteEpochs);
    
    for s = 1:length(stages)
        stage = stages{s};
        stageMask = obj.stageMasks.(stage);
        
        % Count epochs for this stage
        stageEpochs = sum(stageMask(1:numCompleteEpochs));
        
        if stageEpochs > 0
            fprintf('    %s: %d epochs\n', stage, stageEpochs);
            
            % Extract data for this stage - FIXED: Use cell array to avoid dimension issues
            stageDataCells = {};
            validEpochCount = 0;
            
            for epoch = 1:numCompleteEpochs
                if stageMask(epoch)
                    startSample = (epoch-1) * samplesPerEpoch + 1;
                    endSample = min(epoch * samplesPerEpoch, length(channelData));
                    epochData = channelData(startSample:endSample);
                    
                    % Ensure column vector
                    if size(epochData, 1) == 1
                        epochData = epochData';
                    end
                    
                    % Only include if not mostly artifacts and has valid data
                    nanRatio = sum(isnan(epochData)) / length(epochData);
                    if nanRatio < 0.5 && ~all(epochData == 0) && ~isempty(epochData)
                        stageDataCells{end+1} = epochData;
                        validEpochCount = validEpochCount + 1;
                    end
                end
            end
            
            % Combine all epoch data into one vector - FIXED CONCATENATION
            if ~isempty(stageDataCells)
                stageData = vertcat(stageDataCells{:});
            else
                stageData = [];
            end
            
            fprintf('    %s: %d valid epochs, %.1f seconds of clean data\n', ...
                stage, validEpochCount, length(stageData)/fs);
            
            if length(stageData) > 10 * fs % At least 10 seconds of data
                try
                    [stagePSD, frequencies] = obj.calculateAdvancedPSD(stageData, fs);
                    [stageBandPower, stageTotalPower] = obj.calculateBandPower(stagePSD, frequencies, freqBands);
                    stageRelativePower = obj.calculateRelativePower(stageBandPower, stageTotalPower, freqBands);
                    
                    % DEBUG: Check if we have valid power values
                    if isfield(stageBandPower, 'Delta') && stageBandPower.Delta > 0
                        fprintf('      Successfully analyzed %s: %.1f seconds, Delta=%.6f μV²\n', ...
                            stage, length(stageData)/fs, stageBandPower.Delta);
                        
                        % Store both absolute and relative power
                        obj.spectralResults.bandPower.(sanitizedName).(stage) = stageBandPower;
                        obj.spectralResults.relativePower.(sanitizedName).stages.(stage) = stageRelativePower;
                    else
                        fprintf('      WARNING: Invalid power values for %s - skipping storage\n', stage);
                    end
                    
                catch ME
                    fprintf('      ERROR in PSD analysis for %s: %s\n', stage, ME.message);
                end
            else
                fprintf('    Insufficient clean data for %s analysis (only %.1f s < 10 s)\n', ...
                    stage, length(stageData)/fs);
            end
        else
            fprintf('    %s: No epochs found\n', stage);
        end
    end
end
        
        function initializeStageMasks(obj, numEpochs)
            % Initialize masks for each sleep stage
            obj.stageMasks = struct();
            
            % Only include sleep stages + WASO, NOT general wake
            stages = [1, 2, 3, 5]; % N1, N2, N3, REM (NO wake stage 0)
            stageNames = {'N1', 'N2', 'N3', 'REM'};
            
            for i = 1:length(stages)
                stage = stages(i);
                stageName = stageNames{i};
                obj.stageMasks.(stageName) = false(1, numEpochs);
                
                for epoch = 1:min(length(obj.numericHypnogram), numEpochs)
                    if obj.numericHypnogram(epoch) == stage
                        obj.stageMasks.(stageName)(epoch) = true;
                    end
                end
            end
            
            % Add WASO as a separate stage (wake within SPT only)
            obj.stageMasks.WASO = false(1, numEpochs);
            wasoMask = obj.createWASOMask(numEpochs * 30 * obj.fs(1));
            % Convert sample mask to epoch mask for WASO
            samplesPerEpoch = 30 * obj.fs(1);
            for epoch = 1:numEpochs
                startSample = (epoch-1) * samplesPerEpoch + 1;
                endSample = min(epoch * samplesPerEpoch, length(wasoMask));
                if any(wasoMask(startSample:endSample))
                    obj.stageMasks.WASO(epoch) = true;
                end
            end
        end

        function calculateCycleSpecificPSD(obj, channelData, channelName, fs, freqBands)
            % Calculate sleep cycle-specific spectral analysis using direct epoch approach
            if isempty(obj.sleepCycles)
                fprintf('  No sleep cycles available for cycle-specific analysis\n');
                return;
            end
            
            fprintf('  Cycle-specific analysis for %s using direct epoch approach...\n', channelName);
            
            % Get unique cycles
            uniqueCycles = unique(obj.sleepCycles(obj.sleepCycles > 0));
            samplesPerEpoch = 30 * fs;
            
            sanitizedName = obj.sanitizeFieldName(channelName);
            obj.spectralResults.sleepCycles.(sanitizedName) = struct();
            
            for cycleIdx = 1:length(uniqueCycles)
                cycleNum = uniqueCycles(cycleIdx);
                
                % Find start and end epochs
                cycleEpochs = find(obj.sleepCycles == cycleNum);
                
                if isempty(cycleEpochs)
                    fprintf('    Cycle %d: No epochs found\n', cycleNum);
                    continue;
                end
                
                startEpoch = min(cycleEpochs);
                endEpoch = max(cycleEpochs);
                
                fprintf('    Cycle %d: epochs %d to %d (%d epochs, %.1f min)\n', ...
                    cycleNum, startEpoch, endEpoch, length(cycleEpochs), length(cycleEpochs) * 0.5);
                
                % Direct sample extraction: Convert epochs to samples
                startSample = (startEpoch - 1) * samplesPerEpoch + 1;
                endSample = min(endEpoch * samplesPerEpoch, length(channelData));
                
                % Extract cycle data directly
                if startSample <= length(channelData) && endSample >= startSample
                    cycleData = channelData(startSample:endSample);
                    
                    % Remove any NaN values from cycle data
                    if any(isnan(cycleData))
                        nanCount = sum(isnan(cycleData));
                        fprintf('      Removing %d NaN values (%.1f%%) from cycle data\n', ...
                            nanCount, nanCount/length(cycleData)*100);
                        cycleData = fillmissing(cycleData, 'linear');
                    end
                    
                    % Check if we have sufficient clean data
                    cycleDuration = length(cycleData) / fs;
                    fprintf('      Clean data: %.1f seconds\n', cycleDuration);
                    
                    if cycleDuration > 60 % At least 1 minute of clean data
                        try
                            [cyclePSD, frequencies] = obj.calculateAdvancedPSD(cycleData, fs);
                            [cycleBandPower, cycleTotalPower] = obj.calculateBandPower(cyclePSD, frequencies, freqBands);
                            cycleRelativePower = obj.calculateRelativePower(cycleBandPower, cycleTotalPower, freqBands);
                            
                            % Store results
                            cycleName = sprintf('Cycle_%d', cycleNum);
                            obj.spectralResults.sleepCycles.(sanitizedName).(cycleName) = struct(...
                                'bandPower', cycleBandPower, ...
                                'relativePower', cycleRelativePower, ...
                                'psd', cyclePSD, ...
                                'frequencies', frequencies, ...
                                'startEpoch', startEpoch, ...
                                'endEpoch', endEpoch, ...
                                'duration_minutes', cycleDuration / 60);
                            
                            fprintf('      Successfully analyzed: %d samples, %.1f min\n', ...
                                length(cycleData), cycleDuration/60);
                            
                        catch ME
                            fprintf('      Analysis error: %s\n', ME.message);
                        end
                    else
                        fprintf('      Insufficient clean data (%.1f s < 60 s)\n', cycleDuration);
                    end
                else
                    fprintf('      Invalid sample range: %d to %d (data length: %d)\n', ...
                        startSample, endSample, length(channelData));
                end
            end
            
            % Check if any cycles were successfully analyzed
            cycleFields = fieldnames(obj.spectralResults.sleepCycles.(sanitizedName));
            if isempty(cycleFields)
                fprintf('  No sleep cycles successfully analyzed for %s\n', channelName);
                obj.spectralResults.sleepCycles = rmfield(obj.spectralResults.sleepCycles, sanitizedName);
            else
                fprintf('  Successfully analyzed %d sleep cycles for %s\n', length(cycleFields), channelName);
            end
        end

        function saveAdditionalSheets(obj, outputFile)
            % Save additional sheets for data quality and sleep statistics
            try
                % Data quality sheet
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
                
                % Sleep statistics sheet
                if ~isempty(obj.numericHypnogram)
                    stats = obj.calculateSleepStatistics();
                    sleepData = {
                        'Total_Recording_Epochs', stats.totalRecordingEpochs;
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
                end
                
                fprintf('Additional sheets saved successfully\n');
                
            catch ME
                fprintf('Warning: Could not save additional sheets: %s\n', ME.message);
            end
        end
        
        function stats = calculateSleepStatistics(obj)
            % Calculate sleep statistics
            if isempty(obj.numericHypnogram)
                stats = [];
                return;
            end

            fprintf('Calculating sleep statistics...\n');

            fs_ref = obj.fs(1);
            samplesPerEpoch = 30 * fs_ref;
            
            % Check if globalArtifactMask exists and has correct length
            if isempty(obj.globalArtifactMask)
                fprintf('Warning: globalArtifactMask not initialized, using default\n');
                totalSamples = length(obj.allChannelData{1});
                obj.globalArtifactMask = false(1, totalSamples);
            else
                totalSamples = length(obj.globalArtifactMask);
            end

            totalEpochs = min(length(obj.numericHypnogram), ceil(totalSamples/samplesPerEpoch));

            stages = [0, 1, 2, 3, 5]; % Wake, N1, N2, N3, REM
            cleanStageCounts = zeros(size(stages));

            % Find Sleep Period Time (SPT) boundaries
            sleepEpochs = find(obj.numericHypnogram >= 1 & obj.numericHypnogram <= 5);
            
            if isempty(sleepEpochs)
                fprintf('  No sleep epochs found in hypnogram\n');
                stats = [];
                return;
            end
            
            sptStart = min(sleepEpochs);
            sptEnd = max(sleepEpochs);
            
            % Calculate statistics for each stage within SPT
            for epoch = sptStart:sptEnd
                if epoch > length(obj.numericHypnogram)
                    continue;
                end
                
                stage = obj.numericHypnogram(epoch);
                stageIdx = find(stages == stage, 1);

                if isempty(stageIdx)
                    continue;
                end

                startSample = (epoch-1) * samplesPerEpoch + 1;
                endSample = min(epoch * samplesPerEpoch, totalSamples);
                
                % Ensure we don't exceed artifact mask bounds
                if startSample <= length(obj.globalArtifactMask) && endSample <= length(obj.globalArtifactMask)
                    epochArtifactMask = obj.globalArtifactMask(startSample:endSample);
                else
                    % If bounds exceeded, assume no artifacts for this epoch
                    epochArtifactMask = false(1, endSample - startSample + 1);
                end

                % Count as clean if less than 50% artifacts
                if mean(epochArtifactMask) <= 0.5
                    cleanStageCounts(stageIdx) = cleanStageCounts(stageIdx) + 1;
                end
            end

            stats = struct();
            stats.totalRecordingEpochs = totalEpochs;
            stats.SPT_startEpoch = sptStart;
            stats.SPT_endEpoch = sptEnd;
            stats.SPT_epochs = length(sptStart:sptEnd);
            stats.totalCleanEpochs = sum(cleanStageCounts);
            
            % TST = Total time spent in actual sleep stages (N1, N2, N3, REM)
            stats.TST_minutes = (cleanStageCounts(2) + cleanStageCounts(3) + cleanStageCounts(4) + cleanStageCounts(5)) * 0.5;
            
            % WASO = Wake time within SPT (stage 0 within SPT boundaries only)
            stats.WASO_minutes = cleanStageCounts(1) * 0.5;
            
            % SPT = TST + WASO (sleep period time from first to last sleep)
            stats.SPT_minutes = stats.TST_minutes + stats.WASO_minutes;

            % Individual stage minutes
            stats.N1_minutes = cleanStageCounts(2) * 0.5;
            stats.N2_minutes = cleanStageCounts(3) * 0.5;
            stats.N3_minutes = cleanStageCounts(4) * 0.5;
            stats.REM_minutes = cleanStageCounts(5) * 0.5;

            % Calculate percentages relative to TST
            if stats.TST_minutes > 0
                stats.N1_percent = (stats.N1_minutes / stats.TST_minutes) * 100;
                stats.N2_percent = (stats.N2_minutes / stats.TST_minutes) * 100;
                stats.N3_percent = (stats.N3_minutes / stats.TST_minutes) * 100;
                stats.REM_percent = (stats.REM_minutes / stats.TST_minutes) * 100;
            else
                stats.N1_percent = 0;
                stats.N2_percent = 0;
                stats.N3_percent = 0;
                stats.REM_percent = 0;
            end
            
            % Calculate sleep efficiency
            stats.sleepEfficiency = (stats.TST_minutes / stats.SPT_minutes) * 100;
            
            fprintf('Sleep Statistics (artifact-corrected):\n');
            fprintf('  SPT: %.1f min (epochs %d-%d)\n', stats.SPT_minutes, sptStart, sptEnd);
            fprintf('  TST: %.1f min\n', stats.TST_minutes);
            fprintf('  WASO: %.1f min\n', stats.WASO_minutes);
            fprintf('  Sleep Efficiency: %.1f%%\n', stats.sleepEfficiency);
            fprintf('  Stage distribution: N1=%.1f%%, N2=%.1f%%, N3=%.1f%%, REM=%.1f%%\n', ...
                stats.N1_percent, stats.N2_percent, stats.N3_percent, stats.REM_percent);
        end
    end
end
