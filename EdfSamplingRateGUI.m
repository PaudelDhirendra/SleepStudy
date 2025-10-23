function EdfSamplingRateGUI
% EDFSAMPLINGRATEGUI GUI for analyzing EEG signal sampling rates in EDF files
% Focuses specifically on EEG channels and their sampling rates

% Create main figure
fig = figure('Name', 'EDF EEG Sampling Rate Analyzer', ...
    'NumberTitle', 'off', ...
    'MenuBar', 'none', ...
    'ToolBar', 'none', ...
    'Position', [100, 100, 1000, 700], ...
    'Resize', 'on');

% Initialize data structure
handles = struct();
handles.rootFolder = pwd;
handles.outputFolder = pwd;
handles.fileInfo = [];
handles.targetEEGSignals = {'C3-M2', 'C4-M1', 'F3-M2', 'F4-M1', 'O1-M2', 'O2-M1'};
handles.eegKeywords = {'EEG', 'C3', 'C4', 'F3', 'F4', 'O1', 'O2', 'CZ', 'FZ', 'PZ'};

% Create UI controls
handles = createEEGUIControls(fig, handles);

% Store handles
guidata(fig, handles);

end

function handles = createEEGUIControls(fig, handles)
% Create UI controls for EEG signal analysis

% Title
uicontrol('Style', 'text', ...
    'String', 'EDF EEG Signal Sampling Rate Analyzer', ...
    'Position', [50, 650, 900, 30], ...
    'FontSize', 18, ...
    'FontWeight', 'bold');

% EDF Files Folder - Centered below title
uicontrol('Style', 'text', ...
    'String', 'EDF Files Folder:', ...
    'Position', [250, 600, 150, 20], ...  % Centered
    'HorizontalAlignment', 'center', ...
    'FontWeight', 'bold');

handles.edt_edf_folder = uicontrol('Style', 'edit', ...
    'String', handles.rootFolder, ...
    'Position', [200, 570, 500, 25], ...  % Centered and wider
    'HorizontalAlignment', 'left');

handles.btn_select_edf = uicontrol('Style', 'pushbutton', ...
    'String', 'Browse', ...
    'Position', [710, 570, 80, 25], ...  % Aligned with edit box
    'Callback', @(~,~) selectEdfFolder(fig));

% Two columns layout
% Left Column - Target EEG signals and EEG Channel Identification
uicontrol('Style', 'text', ...
    'String', 'Target EEG Signals to Analyze:', ...
    'Position', [50, 520, 250, 20], ...  % Left column
    'HorizontalAlignment', 'left', ...
    'FontWeight', 'bold');

targetSignalsStr = strjoin(handles.targetEEGSignals, ', ');
handles.txt_target_signals = uicontrol('Style', 'text', ...
    'String', sprintf('Targets: %s', targetSignalsStr), ...
    'Position', [50, 480, 400, 14], ...  % Left column, taller for text wrap
    'HorizontalAlignment', 'center', ...
    'BackgroundColor', [0.9, 0.95, 0.9]);

% EEG Channel Identification
uicontrol('Style', 'text', ...
    'String', 'EEG Channel Identification:', ...
    'Position', [50, 440, 200, 20], ...  % Left column
    'HorizontalAlignment', 'left', ...
    'FontWeight', 'bold');

eegKeywordsStr = strjoin(handles.eegKeywords, ', ');
uicontrol('Style', 'text', ...
    'String', sprintf('EEG Keywords: %s', eegKeywordsStr), ...
    'Position', [50, 400, 400, 14], ...  % Left column, taller for text wrap
    'HorizontalAlignment', 'center', ...
    'BackgroundColor', [0.95, 0.95, 0.9]);

% Right Column - Analysis strategy
uicontrol('Style', 'text', ...
    'String', 'Analysis Strategy:', ...
    'Position', [500, 520, 150, 20], ...  % Right column
    'HorizontalAlignment', 'left', ...
    'FontWeight', 'bold');

analysisText = {'1. Scan EDF headers to identify all available signals', ...
                '2. Identify EEG channels using keywords and mapping', ...
                '3. Extract sampling rates for all EEG channels', ...
                '4. Map channel names to standard nomenclature', ...
                '5. Generate comprehensive EEG sampling rate report'};

for i = 1:length(analysisText)
    uicontrol('Style', 'text', ...
        'String', analysisText{i}, ...
        'Position', [520, 490 - (i-1)*22, 400, 20], ...  % Right column
        'HorizontalAlignment', 'left', ...
        'FontSize', 10);
end

% Action buttons - Centered below the two columns
buttonWidth = 150;
buttonHeight = 40;
buttonSpacing = 20;
totalButtonsWidth = 3*buttonWidth + 2*buttonSpacing;
startX = (1000 - totalButtonsWidth) / 2; % Center in 1000px width

handles.btn_analyze = uicontrol('Style', 'pushbutton', ...
    'String', 'Scan EEG Signals', ...
    'Position', [startX, 350, buttonWidth, buttonHeight], ...
    'FontSize', 10, ...  % Smaller font for the longer text
    'FontWeight', 'bold', ...
    'BackgroundColor', [0.8, 0.9, 0.8], ...
    'Callback', @(~,~) analyzeEEGSignals(fig));

handles.btn_export = uicontrol('Style', 'pushbutton', ...
    'String', 'Export Results', ...
    'Position', [startX + buttonWidth + buttonSpacing, 350, buttonWidth, buttonHeight], ...
    'FontSize', 12, ...
    'FontWeight', 'bold', ...
    'BackgroundColor', [0.8, 0.8, 0.9], ...
    'Enable', 'off', ...
    'Callback', @(~,~) exportEEGResults(fig));

handles.btn_summary = uicontrol('Style', 'pushbutton', ...
    'String', 'Show Summary', ...
    'Position', [startX + 2*(buttonWidth + buttonSpacing), 350, buttonWidth, buttonHeight], ...
    'FontSize', 12, ...
    'FontWeight', 'bold', ...
    'BackgroundColor', [0.9, 0.9, 0.8], ...
    'Enable', 'off', ...
    'Callback', @(~,~) showEEGSummary(fig));

% Results table - Centered below buttons
uicontrol('Style', 'text', ...
    'String', 'EEG Signal Sampling Rate Analysis Results:', ...
    'Position', [50, 300, 900, 20], ...  % Centered
    'HorizontalAlignment', 'center', ...
    'FontWeight', 'bold');

% Create table for results
columnNames = {'File', 'Channel Type', 'Original Label', 'Mapped Label', 'Sampling Rate (Hz)', 'Samples/Record', 'Record Duration (s)', 'Status'};
handles.results_table = uitable('Parent', fig, ...
    'Position', [50, 130, 900, 160], ...  % Adjusted position
    'ColumnName', columnNames, ...
    'ColumnWidth', {120, 100, 150, 120, 120, 100, 120, 100}, ...
    'RowName', []);

% Status bar - Below results table
handles.txt_status = uicontrol('Style', 'text', ...
    'String', 'Ready to scan for EEG signals and sampling rates', ...
    'Position', [50, 100, 900, 20], ...
    'HorizontalAlignment', 'center', ...  % Centered
    'BackgroundColor', [0.95, 0.95, 0.95]);

% Progress - Below status bar
handles.txt_progress = uicontrol('Style', 'text', ...
    'String', '', ...
    'Position', [50, 70, 900, 20], ...
    'HorizontalAlignment', 'center', ...  % Centered
    'BackgroundColor', [0.9, 0.9, 0.9]);

end

function selectEdfFolder(fig)
    handles = guidata(fig);
    folder_name = uigetdir(handles.rootFolder, 'Select Folder with EDF Files');
    
    if ischar(folder_name)
        handles.rootFolder = folder_name;
        set(handles.edt_edf_folder, 'String', folder_name);
        guidata(fig, handles);
    end
end

function analyzeEEGSignals(fig)
    handles = guidata(fig);
    
    % Disable button during processing
    set(handles.btn_analyze, 'Enable', 'off');
    set(handles.txt_status, 'String', 'Scanning EDF files for EEG signals and sampling rates...');
    set(handles.txt_progress, 'String', '');
    drawnow;
    
    try
        % Get all EDF files
        edfFiles = findEdfFilesRecursive(handles.rootFolder);
        
        if isempty(edfFiles)
            set(handles.txt_status, 'String', 'No EDF files found.');
            set(handles.btn_analyze, 'Enable', 'on');
            return;
        end
        
        set(handles.txt_status, 'String', sprintf('Found %d EDF files. Scanning for EEG signals...', length(edfFiles)));
        
        % Initialize results
        allResults = {};
        fileInfo = [];
        targetSignals = handles.targetEEGSignals;
        eegKeywords = handles.eegKeywords;
        
        % Process each EDF file
        for fileIdx = 1:length(edfFiles)
            currentFile = edfFiles{fileIdx};
            [filePath, fileName, ext] = fileparts(currentFile);
            fullFileName = [fileName, ext];
            
% Update progress with file count
progress = round(fileIdx/length(edfFiles) * 100);
progressText = sprintf('Processing: %s (%d/%d files - %d%%)', fileName, fileIdx, length(edfFiles), progress);
set(handles.txt_progress, 'String', progressText);
drawnow;
            
            try
                % Step 1: Scan EDF header to get all available signals and sampling rates
                [header, signalHeaders, scanSuccess, allSignalLabels, samplingRates, samplesPerRecord, recordDuration] = scanEdfHeaderWithRates(currentFile);
                
                if scanSuccess && ~isempty(allSignalLabels)
                    % Step 2: Identify EEG channels
                    [eegChannels, channelTypes] = identifyEEGChannels(allSignalLabels, eegKeywords);
                    
                    % Step 3: Map EEG channel names
                    mappedLabels = ChannelMappingHelper(allSignalLabels);
                    
                    fprintf('\n=== File: %s ===\n', fullFileName);
                    fprintf('Total signals: %d\n', length(allSignalLabels));
                    fprintf('EEG signals identified: %d\n', length(eegChannels));
                    
                    if ~isempty(eegChannels)
                        % Store results for each EEG channel
                        for i = 1:length(eegChannels)
                            chIdx = eegChannels(i);
                            resultRow = {fullFileName, channelTypes{i}, allSignalLabels{chIdx}, ...
                                        mappedLabels{chIdx}, samplingRates(chIdx), ...
                                        samplesPerRecord(chIdx), recordDuration, 'Success'};
                            allResults{end+1} = resultRow;
                            
                            % Store detailed info
                            fileInfo(end+1).fileName = fullFileName;
                            fileInfo(end).fullPath = currentFile;
                            fileInfo(end).channelType = channelTypes{i};
                            fileInfo(end).originalLabel = allSignalLabels{chIdx};
                            fileInfo(end).mappedLabel = mappedLabels{chIdx};
                            fileInfo(end).samplingRate = samplingRates(chIdx);
                            fileInfo(end).samplesPerRecord = samplesPerRecord(chIdx);
                            fileInfo(end).recordDuration = recordDuration;
                            fileInfo(end).isEEG = true;
                            fileInfo(end).isTarget = any(strcmp(targetSignals, mappedLabels{chIdx}));
                        end
                        
                        % Also check for target signals that might have been missed
                        for i = 1:length(targetSignals)
                            targetSignal = targetSignals{i};
                            if ~any(strcmp(mappedLabels(eegChannels), targetSignal))
                                % Target signal not found in EEG channels
                                resultRow = {fullFileName, 'Target (Missing)', 'N/A', targetSignal, ...
                                            0, 0, recordDuration, 'Not Found'};
                                allResults{end+1} = resultRow;
                                
                                fileInfo(end+1).fileName = fullFileName;
                                fileInfo(end).fullPath = currentFile;
                                fileInfo(end).channelType = 'Target (Missing)';
                                fileInfo(end).originalLabel = 'N/A';
                                fileInfo(end).mappedLabel = targetSignal;
                                fileInfo(end).samplingRate = 0;
                                fileInfo(end).samplesPerRecord = 0;
                                fileInfo(end).recordDuration = recordDuration;
                                fileInfo(end).isEEG = false;
                                fileInfo(end).isTarget = true;
                            end
                        end
                    else
                        % No EEG channels found
                        fprintf('  No EEG channels identified\n');
                        for i = 1:length(targetSignals)
                            resultRow = {fullFileName, 'Target (No EEG)', 'N/A', targetSignals{i}, ...
                                        0, 0, recordDuration, 'No EEG Channels'};
                            allResults{end+1} = resultRow;
                            
                            fileInfo(end+1).fileName = fullFileName;
                            fileInfo(end).fullPath = currentFile;
                            fileInfo(end).channelType = 'Target (No EEG)';
                            fileInfo(end).originalLabel = 'N/A';
                            fileInfo(end).mappedLabel = targetSignals{i};
                            fileInfo(end).samplingRate = 0;
                            fileInfo(end).samplesPerRecord = 0;
                            fileInfo(end).recordDuration = recordDuration;
                            fileInfo(end).isEEG = false;
                            fileInfo(end).isTarget = true;
                        end
                    end
                    
                    % Add non-EEG summary if there are many non-EEG channels
                    nonEEGcount = length(allSignalLabels) - length(eegChannels);
                    if nonEEGcount > 0
                        resultRow = {fullFileName, 'Non-EEG', sprintf('%d other channels', nonEEGcount), ...
                                    'Various', 0, 0, recordDuration, sprintf('%d non-EEG', nonEEGcount)};
                        allResults{end+1} = resultRow;
                    end
                    
                else
                    % File scan failed
                    fprintf('  Failed to scan EDF header\n');
                    for i = 1:length(targetSignals)
                        resultRow = {fullFileName, 'Target (Error)', 'N/A', targetSignals{i}, ...
                                    0, 0, 0, 'Scan Failed'};
                        allResults{end+1} = resultRow;
                        
                        fileInfo(end+1).fileName = fullFileName;
                        fileInfo(end).fullPath = currentFile;
                        fileInfo(end).channelType = 'Target (Error)';
                        fileInfo(end).originalLabel = 'N/A';
                        fileInfo(end).mappedLabel = targetSignals{i};
                        fileInfo(end).samplingRate = 0;
                        fileInfo(end).samplesPerRecord = 0;
                        fileInfo(end).recordDuration = 0;
                        fileInfo(end).isEEG = false;
                        fileInfo(end).isTarget = true;
                    end
                end
                
            catch ME
                % File processing error
                fprintf('  Error processing file: %s\n', ME.message);
                for i = 1:length(targetSignals)
                    resultRow = {fullFileName, 'Target (Error)', 'N/A', targetSignals{i}, ...
                                0, 0, 0, sprintf('Error: %s', ME.message)};
                    allResults{end+1} = resultRow;
                    
                    fileInfo(end+1).fileName = fullFileName;
                    fileInfo(end).fullPath = currentFile;
                    fileInfo(end).channelType = 'Target (Error)';
                    fileInfo(end).originalLabel = 'N/A';
                    fileInfo(end).mappedLabel = targetSignals{i};
                    fileInfo(end).samplingRate = 0;
                    fileInfo(end).samplesPerRecord = 0;
                    fileInfo(end).recordDuration = 0;
                    fileInfo(end).isEEG = false;
                    fileInfo(end).isTarget = true;
                end
            end
        end
        
        % Update results table
        if ~isempty(allResults)
            tableData = vertcat(allResults{:});
            set(handles.results_table, 'Data', tableData);
        end
        
        % Store results and calculate statistics
        handles.fileInfo = fileInfo;
        handles.analysisStats = calculateEEGStatistics(fileInfo, targetSignals);
        
        % Update status
        eegCount = sum([fileInfo.isEEG]);
        targetFound = sum([fileInfo.isTarget] & [fileInfo.isEEG]);
        set(handles.txt_status, 'String', sprintf('Analysis complete! Processed %d files, found %d EEG signals (%d target)', ...
            length(edfFiles), eegCount, targetFound));
        set(handles.txt_progress, 'String', '');
        
        % Enable export and summary buttons
        set(handles.btn_export, 'Enable', 'on');
        set(handles.btn_summary, 'Enable', 'on');
        
    catch ME
        set(handles.txt_status, 'String', sprintf('Analysis error: %s', ME.message));
    end
    
    set(handles.btn_analyze, 'Enable', 'on');
    guidata(fig, handles);
end

function [eegChannels, channelTypes] = identifyEEGChannels(signalLabels, eegKeywords)
% Identify EEG channels based on keywords
    eegChannels = [];
    channelTypes = {};
    
    for i = 1:length(signalLabels)
        label = upper(strtrim(signalLabels{i}));
        isEEG = false;
        channelType = 'Other';
        
        % Check for EEG keywords
        for k = 1:length(eegKeywords)
            if contains(label, upper(eegKeywords{k}))
                isEEG = true;
                if contains(label, 'ECG') || contains(label, 'EKG')
                    channelType = 'ECG';
                elseif contains(label, 'EMG')
                    channelType = 'EMG';
                elseif contains(label, 'EOG')
                    channelType = 'EOG';
                else
                    channelType = 'EEG';
                end
                break;
            end
        end
        
        % Additional EEG patterns
        if ~isEEG
            % Common EEG patterns: C3, F4, O2, etc.
            eegPattern = '^(C[0-9]|F[0-9]|O[0-9]|P[0-9]|T[0-9]|A[0-9])';
            if ~isempty(regexp(label, eegPattern, 'once'))
                isEEG = true;
                channelType = 'EEG';
            end
        end
        
        if isEEG
            eegChannels(end+1) = i;
            channelTypes{end+1} = channelType;
        end
    end
end

function [header, signalHeaders, success, signalLabels, samplingRates, samplesPerRecord, recordDuration] = scanEdfHeaderWithRates(filename)
% Scan EDF header and extract sampling rates - CORRECTED VERSION
    success = false;
    header = [];
    signalHeaders = [];
    signalLabels = {};
    samplingRates = [];
    samplesPerRecord = [];
    recordDuration = 0;
    
    try
        % Use BlockEdfLoadClass following the pattern from BlockEdfSummarizeClass
        edfObj = BlockEdfLoadClass(filename);
        edfObj.numCompToLoad = 2; % Load header and signal header
        edfObj = edfObj.blockEdfLoad();
        
        % Access data through edf property (like BlockEdfSummarizeClass does)
        if isprop(edfObj, 'edf') && ~isempty(edfObj.edf) && isfield(edfObj.edf, 'header')
            header = edfObj.edf.header;
            signalHeaders = edfObj.edf.signalHeader;
            
            % Extract signal labels and sampling rates
            if ~isempty(signalHeaders)
                signalLabels = {signalHeaders.signal_labels};
                
                % Calculate sampling rates from samples_in_record and record duration
                samplesPerRecord = [signalHeaders.samples_in_record];
                recordDuration = header.data_record_duration;
                
                if recordDuration > 0
                    samplingRates = samplesPerRecord / recordDuration;
                else
                    samplingRates = samplesPerRecord; % Fallback
                end
                
                success = true;
                fprintf('  Successfully extracted sampling rates for %d signals\n', length(signalLabels));
            end
        end
        
    catch ME
        fprintf('  BlockEdfLoadClass approach failed: %s\n', ME.message);
        
        % Fallback to direct EDF reading
        try
            [header, signalHeaders] = readEdfHeaderDirect(filename);
            
            if ~isempty(signalHeaders)
                signalLabels = {signalHeaders.signal_labels};
                samplingRates = [signalHeaders.sample_rate];
                samplesPerRecord = [signalHeaders.samples_in_record];
                recordDuration = header.data_record_duration;
                
                success = true;
                fprintf('  Fallback: extracted rates from direct header reading\n');
            end
        catch ME2
            fprintf('  All approaches failed: %s\n', ME2.message);
            success = false;
        end
    end
end

function [header, signalHeaders] = readEdfHeaderDirect(filename)
% Direct EDF header reading implementation
    fid = fopen(filename, 'r', 'ieee-le');
    if fid == -1
        error('Cannot open file: %s', filename);
    end
    
    header = struct();
    signalHeaders = [];
    
    try
        % Read fixed header (256 bytes)
        header.version = str2double(char(fread(fid, 8, 'char')'));
        header.patient_id = strtrim(char(fread(fid, 80, 'char')'));
        header.recording_id = strtrim(char(fread(fid, 80, 'char')'));
        header.startdate = strtrim(char(fread(fid, 8, 'char')'));
        header.starttime = strtrim(char(fread(fid, 8, 'char')'));
        header.header_bytes = str2double(char(fread(fid, 8, 'char')'));
        header.reserved = strtrim(char(fread(fid, 44, 'char')'));
        header.num_data_records = str2double(char(fread(fid, 8, 'char')'));
        header.data_record_duration = str2double(char(fread(fid, 8, 'char')'));
        header.num_signals = str2double(char(fread(fid, 4, 'char')'));
        
        if header.num_signals == 0
            fclose(fid);
            return;
        end
        
        % Initialize signal headers structure
        signalHeaders = struct('signal_labels', {}, 'sample_rate', {}, 'samples_in_record', {}, 'record_duration', {});
        
        % Read signal labels (16 bytes each)
        for i = 1:header.num_signals
            signalHeaders(i).signal_labels = strtrim(char(fread(fid, 16, 'char')'));
        end
        
        % Skip other signal header fields we don't need for sampling rate
        bytes_to_skip = 80 + 8 + 8 + 8 + 8 + 80; % transducer + phys_dim + phys_min + phys_max + dig_min + dig_max + prefilter
        fseek(fid, bytes_to_skip * header.num_signals, 'cof');
        
        % Read samples per data record (8 bytes each) - THIS GIVES US SAMPLING RATE
        for i = 1:header.num_signals
            samples_str = strtrim(char(fread(fid, 8, 'char')'));
            signalHeaders(i).samples_in_record = str2double(samples_str);
            
            % Calculate sampling rate
            if header.data_record_duration > 0
                signalHeaders(i).sample_rate = signalHeaders(i).samples_in_record / header.data_record_duration;
            else
                signalHeaders(i).sample_rate = signalHeaders(i).samples_in_record; % Fallback
            end
            signalHeaders(i).record_duration = header.data_record_duration;
        end
        
    catch ME
        fclose(fid);
        rethrow(ME);
    end
    
    fclose(fid);
end

function stats = calculateEEGStatistics(fileInfo, targetSignals)
% Calculate statistics for EEG analysis
    stats = struct();
    
    if isempty(fileInfo)
        return;
    end
    
    % Filter EEG channels only
    eegInfo = fileInfo([fileInfo.isEEG]);
    targetInfo = fileInfo([fileInfo.isTarget] & [fileInfo.isEEG]);
    
    % Basic counts
    stats.totalFiles = length(unique({fileInfo.fileName}));
    stats.totalChannelsAnalyzed = length(fileInfo);
    stats.eegChannelsFound = length(eegInfo);
    stats.targetChannelsFound = length(targetInfo);
    
    % Sampling rate statistics
    if ~isempty(eegInfo)
        eegRates = [eegInfo.samplingRate];
        stats.samplingStats.allEEG = struct(...
            'mean', mean(eegRates), ...
            'std', std(eegRates), ...
            'min', min(eegRates), ...
            'max', max(eegRates), ...
            'unique', unique(eegRates), ...
            'count', length(eegRates) ...
        );
    end
    
    if ~isempty(targetInfo)
        targetRates = [targetInfo.samplingRate];
        stats.samplingStats.targetEEG = struct(...
            'mean', mean(targetRates), ...
            'std', std(targetRates), ...
            'min', min(targetRates), ...
            'max', max(targetRates), ...
            'unique', unique(targetRates), ...
            'count', length(targetRates) ...
        );
    end
    
    % Statistics by channel type
    channelTypes = unique({fileInfo.channelType});
    stats.byType = struct();
    for i = 1:length(channelTypes)
        type = channelTypes{i};
        typeMask = strcmp({fileInfo.channelType}, type);
        typeInfo = fileInfo(typeMask);
        
        if ~isempty(typeInfo)
            typeRates = [typeInfo.samplingRate];
            stats.byType.(matlab.lang.makeValidName(type)) = struct(...
                'type', type, ...
                'count', length(typeInfo), ...
                'meanRate', mean(typeRates), ...
                'stdRate', std(typeRates) ...
            );
        end
    end
    
    % Target signal availability
    stats.targetAvailability = struct();
    for i = 1:length(targetSignals)
        signal = targetSignals{i};
        signalMask = strcmp({fileInfo.mappedLabel}, signal) & [fileInfo.isEEG];
        foundCount = sum(signalMask);
        totalFiles = stats.totalFiles;
        
        stats.targetAvailability.(strrep(signal, '-', '_')) = struct(...
            'signal', signal, ...
            'foundInFiles', foundCount, ...
            'availability', foundCount / totalFiles * 100, ...
            'meanSamplingRate', mean([fileInfo(signalMask).samplingRate]) ...
        );
    end
end

function showEEGSummary(fig)
    handles = guidata(fig);
    
    if isempty(handles.analysisStats)
        msgbox('No analysis results available. Please run analysis first.', 'No Data');
        return;
    end
    
    stats = handles.analysisStats;
    targetSignals = handles.targetEEGSignals;
    
    % Create summary message
    summaryText = sprintf('EEG SIGNAL SAMPLING RATE ANALYSIS SUMMARY\n\n');
    
    summaryText = sprintf('%sOverall Statistics:\n', summaryText);
    summaryText = sprintf('%s  Files Processed: %d\n', summaryText, stats.totalFiles);
    summaryText = sprintf('%s  Total Channels Analyzed: %d\n', summaryText, stats.totalChannelsAnalyzed);
    summaryText = sprintf('%s  EEG Channels Found: %d\n', summaryText, stats.eegChannelsFound);
    summaryText = sprintf('%s  Target EEG Signals Found: %d\n\n', summaryText, stats.targetChannelsFound);
    
    if isfield(stats.samplingStats, 'allEEG')
        eegStats = stats.samplingStats.allEEG;
        summaryText = sprintf('%sAll EEG Signals Sampling Rates:\n', summaryText);
        summaryText = sprintf('%s  Mean: %.1f Hz\n', summaryText, eegStats.mean);
        summaryText = sprintf('%s  Range: %.1f - %.1f Hz\n', summaryText, eegStats.min, eegStats.max);
        summaryText = sprintf('%s  Unique Rates: %s\n\n', summaryText, mat2str(eegStats.unique));
    end
    
    if isfield(stats.samplingStats, 'targetEEG')
        targetStats = stats.samplingStats.targetEEG;
        summaryText = sprintf('%sTarget EEG Signals Sampling Rates:\n', summaryText);
        summaryText = sprintf('%s  Mean: %.1f Hz\n', summaryText, targetStats.mean);
        summaryText = sprintf('%s  Range: %.1f - %.1f Hz\n', summaryText, targetStats.min, targetStats.max);
        summaryText = sprintf('%s  Unique Rates: %s\n\n', summaryText, mat2str(targetStats.unique));
    end
    
    summaryText = sprintf('%sTarget Signal Availability:\n', summaryText);
    for i = 1:length(targetSignals)
        signal = targetSignals{i};
        fieldName = strrep(signal, '-', '_');
        if isfield(stats.targetAvailability, fieldName)
            avail = stats.targetAvailability.(fieldName);
            summaryText = sprintf('%s  %s: %d/%d files (%.1f%%)', ...
                summaryText, signal, avail.foundInFiles, stats.totalFiles, avail.availability);
            if avail.foundInFiles > 0
                summaryText = sprintf('%s, avg rate: %.1f Hz\n', summaryText, avail.meanSamplingRate);
            else
                summaryText = sprintf('%s\n', summaryText);
            end
        end
    end
    
    msgbox(summaryText, 'EEG Sampling Rate Analysis Summary');
end

function exportEEGResults(fig)
    handles = guidata(fig);
    
    if isempty(handles.fileInfo)
        msgbox('No results to export. Please run analysis first.', 'No Data');
        return;
    end
    
    try
        % Let user choose output file
        [filename, pathname] = uiputfile('*.xlsx', 'Save EEG Sampling Rate Results As', ...
            fullfile(handles.outputFolder, 'EDF_EEG_Sampling_Rate_Analysis.xlsx'));
        
        if isequal(filename, 0) || isequal(pathname, 0)
            return;
        end
        
        outputFile = fullfile(pathname, filename);
        
        % Prepare data for Excel
        fileInfo = handles.fileInfo;
        excelData = cell(length(fileInfo) + 1, 11);
        
        % Create header
        excelData(1, :) = {'File Name', 'Channel Type', 'Original Label', 'Mapped Label', ...
                          'Sampling Rate (Hz)', 'Samples/Record', 'Record Duration (s)', ...
                          'Is EEG', 'Is Target', 'Full Path', 'Status'};
        
        % Fill data
        for i = 1:length(fileInfo)
            excelData{i+1, 1} = fileInfo(i).fileName;
            excelData{i+1, 2} = fileInfo(i).channelType;
            excelData{i+1, 3} = fileInfo(i).originalLabel;
            excelData{i+1, 4} = fileInfo(i).mappedLabel;
            excelData{i+1, 5} = fileInfo(i).samplingRate;
            excelData{i+1, 6} = fileInfo(i).samplesPerRecord;
            excelData{i+1, 7} = fileInfo(i).recordDuration;
            excelData{i+1, 8} = fileInfo(i).isEEG;
            excelData{i+1, 9} = fileInfo(i).isTarget;
            excelData{i+1, 10} = fileInfo(i).fullPath;
            excelData{i+1, 11} = ifelse(fileInfo(i).samplingRate > 0, 'Success', 'Not Found/Error');
        end
        
        % Write to Excel
        xlswrite(outputFile, excelData, 'EEG_Sampling_Rates');
        
        % Write statistics
        if ~isempty(handles.analysisStats)
            writeEEGStatisticsToExcel(outputFile, handles.analysisStats, handles.targetEEGSignals);
        end
        
        msgbox(sprintf('EEG sampling rate results exported to:\n%s', outputFile), 'Export Complete');
        
    catch ME
        msgbox(sprintf('Export failed: %s', ME.message), 'Export Error');
    end
end

function writeEEGStatisticsToExcel(outputFile, stats, targetSignals)
% Write EEG statistics to Excel
    statsData = {};
    
    % Overall statistics
    statsData{1,1} = 'EEG SAMPLING RATE ANALYSIS STATISTICS';
    statsData{3,1} = 'Files Processed'; statsData{3,2} = stats.totalFiles;
    statsData{4,1} = 'Total Channels Analyzed'; statsData{4,2} = stats.totalChannelsAnalyzed;
    statsData{5,1} = 'EEG Channels Found'; statsData{5,2} = stats.eegChannelsFound;
    statsData{6,1} = 'Target EEG Signals Found'; statsData{6,2} = stats.targetChannelsFound;
    
    % Sampling rate statistics
    if isfield(stats.samplingStats, 'allEEG')
        eegStats = stats.samplingStats.allEEG;
        statsData{8,1} = 'ALL EEG SIGNALS SAMPLING RATE STATISTICS';
        statsData{9,1} = 'Mean (Hz)'; statsData{9,2} = eegStats.mean;
        statsData{10,1} = 'Standard Deviation (Hz)'; statsData{10,2} = eegStats.std;
        statsData{11,1} = 'Minimum (Hz)'; statsData{11,2} = eegStats.min;
        statsData{12,1} = 'Maximum (Hz)'; statsData{12,2} = eegStats.max;
        statsData{13,1} = 'Unique Rates (Hz)'; statsData{13,2} = mat2str(eegStats.unique);
        statsData{14,1} = 'Channel Count'; statsData{14,2} = eegStats.count;
    end
    
    if isfield(stats.samplingStats, 'targetEEG')
        targetStats = stats.samplingStats.targetEEG;
        statsData{16,1} = 'TARGET EEG SIGNALS SAMPLING RATE STATISTICS';
        statsData{17,1} = 'Mean (Hz)'; statsData{17,2} = targetStats.mean;
        statsData{18,1} = 'Standard Deviation (Hz)'; statsData{18,2} = targetStats.std;
        statsData{19,1} = 'Minimum (Hz)'; statsData{19,2} = targetStats.min;
        statsData{20,1} = 'Maximum (Hz)'; statsData{20,2} = targetStats.max;
        statsData{21,1} = 'Unique Rates (Hz)'; statsData{21,2} = mat2str(targetStats.unique);
        statsData{22,1} = 'Channel Count'; statsData{22,2} = targetStats.count;
    end
    
    % Target signal availability
    row = 24;
    statsData{row,1} = 'TARGET SIGNAL AVAILABILITY';
    row = row + 1;
    statsData{row,1} = 'Target Signal';
    statsData{row,2} = 'Found In Files';
    statsData{row,3} = 'Total Files';
    statsData{row,4} = 'Availability (%)';
    statsData{row,5} = 'Mean Sampling Rate (Hz)';
    
    for i = 1:length(targetSignals)
        signal = targetSignals{i};
        fieldName = strrep(signal, '-', '_');
        if isfield(stats.targetAvailability, fieldName)
            avail = stats.targetAvailability.(fieldName);
            row = row + 1;
            statsData{row,1} = signal;
            statsData{row,2} = avail.foundInFiles;
            statsData{row,3} = stats.totalFiles;
            statsData{row,4} = avail.availability;
            if avail.foundInFiles > 0
                statsData{row,5} = avail.meanSamplingRate;
            else
                statsData{row,5} = 'N/A';
            end
        end
    end
    
    % Write to Excel
    try
        xlswrite(outputFile, statsData, 'Statistics');
    catch
        % If writing to second sheet fails, create a separate file
        [path, name, ~] = fileparts(outputFile);
        statsFile = fullfile(path, [name '_Statistics.xlsx']);
        xlswrite(statsFile, statsData);
    end
end

function result = ifelse(condition, trueValue, falseValue)
% Simple if-else helper function
    if condition
        result = trueValue;
    else
        result = falseValue;
    end
end

% Include helper functions
function edfFiles = findEdfFilesRecursive(rootFolder)
% Find all EDF files recursively in folder structure
    edfFiles = {};
    
    % Get all files and folders
    items = dir(rootFolder);
    dirFlags = [items.isdir];
    subFolders = items(dirFlags);
    files = items(~dirFlags);
    
    % Process files in current folder
    for i = 1:length(files)
        [~, ~, ext] = fileparts(files(i).name);
        if strcmpi(ext, '.edf')
            edfFiles{end+1} = fullfile(rootFolder, files(i).name);
        end
    end
    
    % Recursively process subfolders (excluding . and ..)
    for i = 1:length(subFolders)
        if ~strcmp(subFolders(i).name, '.') && ~strcmp(subFolders(i).name, '..')
            subFolderPath = fullfile(rootFolder, subFolders(i).name);
            subFolderEdfFiles = findEdfFilesRecursive(subFolderPath);
            edfFiles = [edfFiles, subFolderEdfFiles];
        end
    end
end

function [header, signalHeaders] = readEdfHeaderBasic(filename)
% Basic EDF header reading implementation (fallback)
    fid = fopen(filename, 'r', 'ieee-le');
    if fid == -1
        error('Cannot open file: %s', filename);
    end
    
    try
        % Read header
        header.version = str2double(char(fread(fid, 8, 'char')'));
        header.patient_id = char(fread(fid, 80, 'char')');
        header.recording_id = char(fread(fid, 80, 'char')');
        header.startdate = char(fread(fid, 8, 'char')');
        header.starttime = char(fread(fid, 8, 'char')');
        header.header_bytes = str2double(char(fread(fid, 8, 'char')'));
        header.reserved = char(fread(fid, 44, 'char')');
        header.num_data_records = str2double(char(fread(fid, 8, 'char')'));
        header.data_record_duration = str2double(char(fread(fid, 8, 'char')'));
        header.num_signals = str2double(char(fread(fid, 4, 'char')'));
        
        % Read signal headers
        for i = 1:header.num_signals
            signalHeaders(i).signal_labels = strtrim(char(fread(fid, 16, 'char')'));
        end
        
        % Skip other signal header fields for simplicity
        fseek(fid, header.header_bytes, 'bof');
        
    catch ME
        fclose(fid);
        rethrow(ME);
    end
    
    fclose(fid);
end

function mappedLabels = ChannelMappingHelper(signalLabels)
% Map channel names to standard nomenclature
    mappedLabels = cell(size(signalLabels));
    
    for i = 1:length(signalLabels)
        label = upper(strtrim(signalLabels{i}));
        
        % Common EEG channel mappings
        if contains(label, 'C3') && contains(label, 'M2')
            mappedLabels{i} = 'C3-M2';
        elseif contains(label, 'C4') && contains(label, 'M1')
            mappedLabels{i} = 'C4-M1';
        elseif contains(label, 'F3') && contains(label, 'M2')
            mappedLabels{i} = 'F3-M2';
        elseif contains(label, 'F4') && contains(label, 'M1')
            mappedLabels{i} = 'F4-M1';
        elseif contains(label, 'O1') && contains(label, 'M2')
            mappedLabels{i} = 'O1-M2';
        elseif contains(label, 'O2') && contains(label, 'M1')
            mappedLabels{i} = 'O2-M1';
        elseif contains(label, 'C3') && contains(label, 'A2')
            mappedLabels{i} = 'C3-A2';
        elseif contains(label, 'C4') && contains(label, 'A1')
            mappedLabels{i} = 'C4-A1';
        elseif contains(label, 'EEG')
            % Extract the main EEG channel name
            eegParts = strsplit(label);
            for j = 1:length(eegParts)
                if contains(eegParts{j}, 'EEG')
                    mappedLabels{i} = eegParts{j};
                    break;
                end
            end
            if isempty(mappedLabels{i})
                mappedLabels{i} = label;
            end
        else
            mappedLabels{i} = label;
        end
    end
end