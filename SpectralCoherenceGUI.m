function varargout = SpectralCoherenceGUI(varargin)
% SPECTRALCOHERENCEGUI MATLAB code for SpectralCoherenceGUI.fig
%      SPECTRALCOHERENCEGUI, by itself, creates a new SPECTRALCOHERENCEGUI or raises the existing
%      singleton*.

% Last Modified by GUIDE v2.5 24-Oct-2025 10:36:29

% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @SpectralCoherenceGUI_OpeningFcn, ...
                   'gui_OutputFcn',  @SpectralCoherenceGUI_OutputFcn, ...
                   'gui_LayoutFcn',  [] , ...
                   'gui_Callback',   []);
if nargin && ischar(varargin{1})
    gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT


% --- Executes just before SpectralCoherenceGUI is made visible.
function SpectralCoherenceGUI_OpeningFcn(hObject, eventdata, handles, varargin)
% This function has no output args, see OutputFcn.
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% varargin   command line arguments to SpectralCoherenceGUI (see VARARGIN)

% Choose default command line output for SpectralCoherenceGUI
handles.output = hObject;

% Set defaults
set(handles.e_analysis_description, 'String', 'Spectral Coherence Analysis');
set(handles.e_prefix, 'String', 'study_');
set(handles.e_xml_suffix, 'String', '.edf.xml');

% Set defaults for processing controls
set(handles.cb_ecg_decontamination, 'Value', 1);
set(handles.e_ecg_channel, 'Enable', 'off');
set(handles.cb_artifact_detection, 'Value', 1);
set(handles.e_artifact_threshold_delta, 'String', '2.5');
set(handles.e_artifact_threshold_delta, 'Enable', 'on');
set(handles.e_artifact_threshold_beta, 'String', '2.0');
set(handles.e_artifact_threshold_beta, 'Enable', 'on');

% Auto-select channels (will be populated when files are processed)
set(handles.e_spectral_channels, 'String', '{''Auto-Select''}');
set(handles.e_coherence_pairs, 'String', '{''Auto-Select''}');
set(handles.e_ecg_channel, 'String', '{''Auto-Select''}');

% Disable run buttons until folders are selected
set(handles.pb_run_spectral, 'Enable', 'off');
set(handles.pb_run_coherence, 'Enable', 'off');
set(handles.pb_run_both, 'Enable', 'off');

% Folder flags
handles.data_folder_path = pwd;
handles.data_folder_path_is_selected = 0;
handles.result_folder_path = pwd;
handles.result_folder_path_is_selected = 0;

% Update handles structure
guidata(hObject, handles);

% UIWAIT makes SpectralCoherenceGUI wait for user response (see UIRESUME)
% uiwait(handles.figure1);


% --- Outputs from this function are returned to the command line.
function varargout = SpectralCoherenceGUI_OutputFcn(hObject, eventdata, handles) 
% varargout  cell array for returning output args (see VARARGOUT);
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Get default command line output from handles structure
varargout{1} = handles.output;


% =========================================================================
% FOLDER SELECTION CALLBACKS
% =========================================================================

% --- Executes on button press in pb_select_data.
function pb_select_data_Callback(hObject, eventdata, handles)
data_folder_path = handles.data_folder_path;
[folder_path, folder_is_selected] = pb_select_data_folder(data_folder_path, 'Select Data Folder');
if folder_is_selected == 1
    set(handles.e_data_folder, 'String', folder_path);
    handles.data_folder_path = folder_path;
    handles.data_folder_path_is_selected = folder_is_selected;
    guidata(hObject, handles);
    updateRunButtons(handles);
end

% --- Executes on button press in pb_select_result.
function pb_select_result_Callback(hObject, eventdata, handles)
result_folder_path = handles.result_folder_path;
[folder_path, folder_is_selected] = pb_select_data_folder(result_folder_path, 'Select Result Folder');
if folder_is_selected == 1
    set(handles.e_result_folder, 'String', folder_path);
    handles.result_folder_path = folder_path;
    handles.result_folder_path_is_selected = folder_is_selected;
    guidata(hObject, handles);
    updateRunButtons(handles);
end

function updateRunButtons(handles)
if handles.data_folder_path_is_selected && handles.result_folder_path_is_selected
    set(handles.pb_run_spectral, 'Enable', 'on');
    set(handles.pb_run_coherence, 'Enable', 'on');
    set(handles.pb_run_both, 'Enable', 'on');
else
    set(handles.pb_run_spectral, 'Enable', 'off');
    set(handles.pb_run_coherence, 'Enable', 'off');
    set(handles.pb_run_both, 'Enable', 'off');
end


% =========================================================================
% PROCESSING CONTROL CALLBACKS
% =========================================================================

% --- Executes on button press in cb_ecg_decontamination.
function cb_ecg_decontamination_Callback(hObject, eventdata, handles)
if get(hObject, 'Value')
    set(handles.e_ecg_channel, 'Enable', 'on');
else
    set(handles.e_ecg_channel, 'Enable', 'off');
end

% --- Executes on button press in cb_artifact_detection.
function cb_artifact_detection_Callback(hObject, eventdata, handles)
if get(hObject, 'Value')
    set(handles.e_artifact_threshold_delta, 'Enable', 'on');
    set(handles.e_artifact_threshold_beta, 'Enable', 'on');
else
    set(handles.e_artifact_threshold_delta, 'Enable', 'off');
    set(handles.e_artifact_threshold_beta, 'Enable', 'off');
end


% =========================================================================
% RUN ANALYSIS CALLBACKS
% =========================================================================

% --- Executes on button press in pb_run_spectral.
function pb_run_spectral_Callback(hObject, eventdata, handles)
runAnalysis(handles, 'spectral');

% --- Executes on button press in pb_run_coherence.
function pb_run_coherence_Callback(hObject, eventdata, handles)
runAnalysis(handles, 'coherence');

% --- Executes on button press in pb_run_both.
function pb_run_both_Callback(hObject, eventdata, handles)
runAnalysis(handles, 'both');


% =========================================================================
% ANALYSIS FUNCTION
% =========================================================================

function runAnalysis(handles, mode)
dataDir = get(handles.e_data_folder, 'String');
resultDir = get(handles.e_result_folder, 'String');
prefix = get(handles.e_prefix, 'String');
xmlSuffix = get(handles.e_xml_suffix, 'String');

% Get processing parameters
denoiseEcg = logical(get(handles.cb_ecg_decontamination, 'Value'));
enableArtifactDetection = logical(get(handles.cb_artifact_detection, 'Value'));
deltaTh = str2double(get(handles.e_artifact_threshold_delta, 'String'));
betaTh = str2double(get(handles.e_artifact_threshold_beta, 'String'));
artifactThresholds = [deltaTh, betaTh];

% Validate thresholds
if isnan(deltaTh) || deltaTh <= 0
    errordlg('Invalid delta threshold. Using default value 2.5', 'Invalid Input');
    deltaTh = 2.5;
    set(handles.e_artifact_threshold_delta, 'String', '2.5');
end

if isnan(betaTh) || betaTh <= 0
    errordlg('Invalid beta threshold. Using default value 2.0', 'Invalid Input');
    betaTh = 2.0;
    set(handles.e_artifact_threshold_beta, 'String', '2.0');
end

fprintf('\n=== STARTING SPECTRAL/COHERENCE ANALYSIS ===\n');
fprintf('Data directory: %s\n', dataDir);
fprintf('Result directory: %s\n', resultDir);
fprintf('Mode: %s\n', mode);
fprintf('XML suffix: %s\n', xmlSuffix);

% Create temporary file list
tempFileList = fullfile(resultDir, 'temp_file_list.xlsx');

% Initialize file tracking variables
fileList = [];
edfFiles = [];
useFileListMethod = false;

try
    % Get matched EDF/XML files using existing function
    fprintf('Searching for EDF/XML file pairs...\n');
    matchedFiles = GetMatchedSleepEdfXmlFiles(dataDir, tempFileList, dataDir, xmlSuffix);
    
    if iscell(matchedFiles) && ~isempty(matchedFiles)
        fileList = matchedFiles{1};
        useFileListMethod = true;
        fprintf('Found file list with %d rows\n', size(fileList, 1));
    else
        % If function doesn't return cell, read from the Excel file
        if exist(tempFileList, 'file')
            fileList = readtable(tempFileList);
            useFileListMethod = true;
            fprintf('Read file list from Excel with %d rows\n', height(fileList));
        else
            error('No EDF/XML file pairs found');
        end
    end
    
    if useFileListMethod
        n = height(fileList) - 1; % Subtract header row
        if n == 0
            error('No EDF files found with matching XML files');
        end
        fprintf('Found %d EDF/XML file pairs using file list method\n', n);
    end
    
catch ME
    % Fallback: try recursive search if the main function fails
    fprintf('Using fallback file search method...\n');
    fprintf('Error in main file search: %s\n', ME.message);
    edfFiles = dir(fullfile(dataDir, '**', '*.edf'));
    if isempty(edfFiles)
        edfFiles = dir(fullfile(dataDir, '*.edf'));
    end
    n = length(edfFiles);
    if n == 0
        errorMsg = sprintf('No EDF files found in: %s\nSearched recursively in subfolders.', dataDir);
        errordlg(errorMsg, 'Error');
        fprintf('ERROR: %s\n', errorMsg);
        return;
    end
    fprintf('Found %d EDF files using fallback method\n', n);
    useFileListMethod = false;
end

% Initialize counters for results tracking
processedFiles = 0;
spectralResults = 0;
coherenceResults = 0;
errors = {};

waitFig = waitbar(0, 'Initializing...');

for k = 1:n
    % Initialize variables for this iteration
    currentFileName = '';
    edfPath = '';
    xmlPath = '';
    edfNameClean = '';
    currentFolder = '';
    
    try
        if useFileListMethod
            % Use the file list from GetMatchedSleepEdfXmlFiles
            if istable(fileList)
                % For table structure
                edfName = fileList.('EDF Name'){k+1};
                edfFolder = fileList.('EDF Folder'){k+1};
                xmlName = fileList.('XML Name'){k+1};
                xmlFolder = fileList.('XML Folder'){k+1};
            else
                % For cell array structure
                edfName = fileList{k+1, 2}; % EDF Name column
                edfFolder = fileList{k+1, 6}; % EDF Folder column
                xmlName = fileList{k+1, 7}; % XML Name column
                xmlFolder = fileList{k+1, 11}; % XML Folder column
            end
            
            edfPath = fullfile(edfFolder, edfName);
            xmlPath = fullfile(xmlFolder, xmlName);
            
            currentFileName = edfName;
            currentProgress = sprintf('Processing %d/%d: %s', k, n, currentFileName);
        else
            % Fallback: use recursive search results
            edfPath = fullfile(edfFiles(k).folder, edfFiles(k).name);
            currentFileName = edfFiles(k).name;
            currentProgress = sprintf('Processing %d/%d: %s', k, n, currentFileName);
            
            % Find XML file using simple method
            [edfFolder, edfNameNoExt, ~] = fileparts(edfPath);
            xmlPath = fullfile(edfFolder, [edfNameNoExt xmlSuffix]);
            if ~exist(xmlPath, 'file')
                xmlPath = fullfile(edfFolder, [edfNameNoExt '.xml']);
            end
        end
        
        waitbar(k/n, waitFig, currentProgress);
        fprintf('\n--- Processing file %d/%d: %s ---\n', k, n, currentFileName);
        
        % Check if files exist
        if ~exist(edfPath, 'file')
            errorMsg = sprintf('EDF file not found: %s', edfPath);
            errors{end+1} = errorMsg;
            fprintf('WARNING: %s\n', errorMsg);
            continue;
        end
        
        if ~exist(xmlPath, 'file')
            errorMsg = sprintf('XML file not found for: %s', currentFileName);
            errors{end+1} = errorMsg;
            fprintf('WARNING: %s\n', errorMsg);
            continue;
        end
        fprintf('Found matching XML: %s\n', xmlPath);

        % AUTO-DETECT CHANNELS for this file
        [autoSpectralChannels, autoCoherencePairs, autoEcgChannels] = detectAvailableChannels(edfPath);
        
        % Update GUI with detected channels (for display only)
        if k == 1 % Only update GUI once with first file's channels
            set(handles.e_spectral_channels, 'String', ['{', sprintf('''%s'',', autoSpectralChannels{1:end-1}), '''', autoSpectralChannels{end}, '''}']);
            set(handles.e_coherence_pairs, 'String', ['{', sprintf('''%s'',', autoCoherencePairs{1:end-1}), '''', autoCoherencePairs{end}, '''}']);
            set(handles.e_ecg_channel, 'String', ['{', sprintf('''%s'',', autoEcgChannels{1:end-1}), '''', autoEcgChannels{end}, '''}']);
            guidata(handles.figure1, handles);
        end
        
        % Create parameters structure with auto-detected channels
        analysisParams = struct();
        analysisParams.denoiseEcg = denoiseEcg;
        analysisParams.ecgName = autoEcgChannels;
        analysisParams.enableArtifactDetection = enableArtifactDetection;
        analysisParams.artifactThreshold = artifactThresholds;
        analysisParams.autoSpectralChannels = autoSpectralChannels;
        analysisParams.autoCoherencePairs = autoCoherencePairs;
        
        % Create subject-specific prefix
        if useFileListMethod
            [~, edfNameClean, ~] = fileparts(edfName);
            currentFolder = edfFolder;
        else
            [~, edfNameClean, ~] = fileparts(edfFiles(k).name);
            currentFolder = edfFiles(k).folder;
        end
        subPrefix = [prefix '_' edfNameClean];
        
        % Create subject-specific result folder
        subjectResultDir = createSubjectResultDir(resultDir, currentFolder, dataDir);
        
        processedFiles = processedFiles + 1;

        % Spectral Analysis with auto-detected channels
        if any(strcmp(mode, {'spectral','both'}))
            fprintf('Starting spectral analysis with auto-selected channels: %s\n', strjoin(autoSpectralChannels, ', '));
            try
                % Create parameters structure for spectral analysis
                spectralParams = struct();
                spectralParams.resultFolder = subjectResultDir;
                spectralParams.outputPrefix = subPrefix;
                spectralParams.denoiseEcg = analysisParams.denoiseEcg;
                spectralParams.ecgName = analysisParams.ecgName;
                spectralParams.enableArtifactDetection = analysisParams.enableArtifactDetection;
                spectralParams.artifactThreshold = analysisParams.artifactThreshold;
                
                % Create spectral analysis object
                spectralObj = SpectralAnalysisClass(edfPath, xmlPath, spectralParams);
                
                % Run analysis on auto-detected channels
                spectralObj.runAnalysis(autoSpectralChannels);
                
                % Save results
                if ~isempty(spectralObj.spectralResults)
                    spectralFn = fullfile(subjectResultDir, [subPrefix '_SpectralResults.xlsx']);
                    spectralObj.saveResults(spectralFn);
                    spectralResults = spectralResults + 1;
                    fprintf('SUCCESS: Generated spectral results\n');
                else
                    spectralFn = fullfile(subjectResultDir, [subPrefix '_SpectralResults.xlsx']);
                    emptyTable = table({'No spectral results generated'}, 'VariableNames', {'Result'});
                    writetable(emptyTable, spectralFn);
                    fprintf('No spectral results generated (saved empty results)\n');
                end
            catch ME
                fprintf('Error in spectral analysis: %s\n', ME.message);
                spectralFn = fullfile(subjectResultDir, [subPrefix '_SpectralResults.xlsx']);
                errorTable = table({sprintf('Error: %s', ME.message)}, 'VariableNames', {'Result'});
                writetable(errorTable, spectralFn);
            end
        end

        % Coherence Analysis with auto-detected channels
        if any(strcmp(mode, {'coherence','both'}))
            fprintf('Starting coherence analysis with auto-selected pairs: %s\n', strjoin(autoCoherencePairs, ', '));
            try
                % Create parameters structure for coherence analysis
                coherenceParams = struct();
                coherenceParams.resultFolder = subjectResultDir;
                coherenceParams.outputPrefix = subPrefix;
                coherenceParams.denoiseEcg = analysisParams.denoiseEcg;
                coherenceParams.ecgName = analysisParams.ecgName;
                coherenceParams.enableArtifactDetection = analysisParams.enableArtifactDetection;
                coherenceParams.artifactThreshold = analysisParams.artifactThreshold;
                
                % Create coherence analysis object
                coherenceObj = CoherenceAnalysisClass(edfPath, xmlPath, coherenceParams);
                coherenceObj.runAnalysis(autoCoherencePairs);
                
                % Save results
                if ~isempty(coherenceObj.coherenceResults)
                    coherenceFn = fullfile(subjectResultDir, [subPrefix '_CoherenceResults.xlsx']);
                    coherenceObj.saveResults(coherenceFn);
                    coherenceResults = coherenceResults + 1;
                    fprintf('SUCCESS: Generated coherence results\n');
                end
            catch ME
                fprintf('Error in coherence analysis: %s\n', ME.message);
            end
        end
        
        fprintf('Completed processing: %s\n', edfNameClean);
        
    catch ME
        % Log error but continue processing other files
        if isempty(currentFileName)
            currentFileName = sprintf('File %d', k);
        end
        errorMsg = sprintf('Error processing %s: %s', currentFileName, ME.message);
        errors{end+1} = errorMsg;
        fprintf('ERROR: %s\n', errorMsg);
        fprintf('Stack trace:\n');
        for i = 1:length(ME.stack)
            fprintf('  %s line %d\n', ME.stack(i).name, ME.stack(i).line);
        end
    end
end

% Clean up temporary file
if exist(tempFileList, 'file')
    delete(tempFileList);
end

if ishandle(waitFig)
    close(waitFig);
end

% Display comprehensive results summary
resultMessage = sprintf(['Analysis Complete!\n\n' ...
                       'Total EDF files found: %d\n' ...
                       'Files successfully processed: %d\n' ...
                       'Successful spectral analyses: %d\n' ...
                       'Successful coherence analyses: %d\n' ...
                       'Errors encountered: %d'], ...
                       n, processedFiles, spectralResults, coherenceResults, length(errors));

if ~isempty(errors)
    resultMessage = sprintf('%s\n\nErrors:\n%s', resultMessage, strjoin(errors, '\n'));
    fprintf('\n=== ERRORS ENCOUNTERED ===\n');
    for i = 1:length(errors)
        fprintf('%s\n', errors{i});
    end
end

fprintf('\n=== ANALYSIS SUMMARY ===\n');
fprintf('Total EDF files: %d\n', n);
fprintf('Successfully processed: %d\n', processedFiles);
fprintf('Spectral results: %d\n', spectralResults);
fprintf('Coherence results: %d\n', coherenceResults);
fprintf('Errors: %d\n', length(errors));
fprintf('========================\n');

msgbox(resultMessage, 'Analysis Complete');


% =========================================================================
% CUSTOM FUNCTIONS
% =========================================================================

function [spectralChannels, coherencePairs, ecgChannels] = detectAvailableChannels(edfPath)
    % Detect available channels from EDF file for auto-selection
    fprintf('Auto-detecting channels from: %s\n', edfPath);
    
    try
        % Load EDF file temporarily to detect channels
        tempLoader = BlockEdfLoadClass(edfPath);
        tempLoader.numCompToLoad = 3;
        tempLoader.SWAP_MIN_MAX = 1;
        tempLoader = tempLoader.blockEdfLoad;
        
        rawChannelNames = tempLoader.signal_labels;
        mappedNames = ChannelMappingHelper(rawChannelNames);
        
        fprintf('Available channels: %s\n', strjoin(mappedNames, ', '));
        
        % Detect spectral channels (standard EEG channels)
        spectralChannels = detectSpectralChannels(mappedNames);
        
        % Detect coherence pairs (standard bipolar pairs)
        coherencePairs = detectCoherencePairs(mappedNames);
        
        % Detect ECG channels
        ecgChannels = detectECGChannels(mappedNames);
        
        fprintf('Auto-detected:\n');
        fprintf('  Spectral channels: %s\n', strjoin(spectralChannels, ', '));
        fprintf('  Coherence pairs: %s\n', strjoin(coherencePairs, ', '));
        fprintf('  ECG channels: %s\n', strjoin(ecgChannels, ', '));
        
    catch ME
        fprintf('Error auto-detecting channels: %s\n', ME.message);
        % Fallback to defaults
        spectralChannels = {'F3-M2', 'F4-M1', 'C3-M2', 'C4-M1', 'O1-M2', 'O2-M1'};
        coherencePairs = {'F3-F4', 'C3-C4', 'O1-O2', 'F3-C3', 'F4-C4', 'C3-O1', 'C4-O2'};
        ecgChannels = {'ECG', 'EKG'};
    end

function spectralChannels = detectSpectralChannels(channelNames)
    % Standard EEG channels for spectral analysis
    standardEEG = {'F3-M2', 'F4-M1', 'C3-M2', 'C4-M1', 'O1-M2', 'O2-M1', 'FZ', 'CZ', 'PZ'};
    spectralChannels = {};
    
    for i = 1:length(standardEEG)
        if any(strcmp(channelNames, standardEEG{i}))
            spectralChannels{end+1} = standardEEG{i};
        end
    end
    
    % Fallback: look for any EEG channels
    if length(spectralChannels) < 4
        eegPatterns = {'F3', 'F4', 'C3', 'C4', 'O1', 'O2', 'FZ', 'CZ', 'PZ', 'FP1', 'FP2', 'A1', 'A2', 'M1', 'M2'};
        foundChannels = {};
        
        for i = 1:length(channelNames)
            for j = 1:length(eegPatterns)
                if contains(upper(channelNames{i}), upper(eegPatterns{j}))
                    foundChannels{end+1} = channelNames{i};
                    break;
                end
            end
        end
        
        % Use up to 8 EEG channels
        if length(foundChannels) > 8
            spectralChannels = foundChannels(1:8);
        else
            spectralChannels = foundChannels;
        end
    end

function coherencePairs = detectCoherencePairs(channelNames)
    % Standard coherence pairs
    standardPairs = {'F3-F4', 'C3-C4', 'O1-O2', 'F3-C3', 'F4-C4', 'C3-O1', 'C4-O2'};
    coherencePairs = {};
    
    % Check which standard pairs are available
    for i = 1:length(standardPairs)
        pair = standardPairs{i};
        channels = strsplit(pair, '-');
        if length(channels) == 2
            ch1 = channels{1};
            ch2 = channels{2};
            % Check if both channels exist (approximate match)
            ch1Found = false;
            ch2Found = false;
            for j = 1:length(channelNames)
                if contains(upper(channelNames{j}), upper(ch1))
                    ch1Found = true;
                end
                if contains(upper(channelNames{j}), upper(ch2))
                    ch2Found = true;
                end
            end
            if ch1Found && ch2Found
                coherencePairs{end+1} = pair;
            end
        end
    end
    
    % Fallback: use available channels to create pairs
    if length(coherencePairs) < 3
        eegChannels = {};
        eegPatterns = {'F3', 'F4', 'C3', 'C4', 'O1', 'O2'};
        for i = 1:length(channelNames)
            for j = 1:length(eegPatterns)
                if contains(upper(channelNames{i}), upper(eegPatterns{j}))
                    eegChannels{end+1} = channelNames{i};
                    break;
                end
            end
        end
        
        % Create simple pairs from available EEG channels
        if length(eegChannels) >= 2
            for i = 1:min(6, length(eegChannels))
                for j = i+1:min(6, length(eegChannels))
                    pairName = sprintf('%s-%s', eegChannels{i}, eegChannels{j});
                    coherencePairs{end+1} = pairName;
                end
            end
        end
    end

function ecgChannels = detectECGChannels(channelNames)
    % Common ECG channel patterns
    ecgPatterns = {'ECG', 'EKG', 'ELECTROCARDIO', 'ELECTRO-CARDIO', 'RIP ECG', 'ECG II', 'ECG1', 'EKG1', 'ECG2', 'EKG2'};
    ecgChannels = {};
    
    for i = 1:length(channelNames)
        currentLabel = upper(channelNames{i});
        for j = 1:length(ecgPatterns)
            if contains(currentLabel, ecgPatterns{j})
                ecgChannels{end+1} = channelNames{i};
                break;
            end
        end
    end
    
    % Fallback: look for any channel containing "ECG" or "EKG"
    if isempty(ecgChannels)
        for i = 1:length(channelNames)
            if contains(upper(channelNames{i}), 'ECG') || contains(upper(channelNames{i}), 'EKG')
                ecgChannels{end+1} = channelNames{i};
            end
        end
    end

function subjectResultDir = createSubjectResultDir(baseResultDir, edfFolder, dataDir)
    % Create subject-specific folder structure preserving original hierarchy
    if strcmp(edfFolder, dataDir)
        % If EDF is in root data directory, use flat structure
        subjectResultDir = baseResultDir;
    else
        % Preserve subfolder structure
        relativePath = strrep(edfFolder, dataDir, '');
        % Clean up the path for use as a folder name
        relativePath = strrep(relativePath, filesep, '_');
        relativePath = strrep(relativePath, ':', '');
        relativePath = strrep(relativePath, ' ', '_');
        % Remove leading and trailing underscores
        relativePath = regexprep(relativePath, '^_+|_+$', '');
        if isempty(relativePath)
            subjectResultDir = baseResultDir;
        else
            subjectResultDir = fullfile(baseResultDir, relativePath);
        end
    end
    
    if ~exist(subjectResultDir, 'dir')
        mkdir(subjectResultDir);
        fprintf('Created result directory: %s\n', subjectResultDir);
    else
        fprintf('Using existing result directory: %s\n', subjectResultDir);
    end


% =========================================================================
% BASIC CALLBACKS (minimal implementation)
% =========================================================================

function e_analysis_description_Callback(hObject, eventdata, handles)
function e_analysis_description_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function e_data_folder_Callback(hObject, eventdata, handles)
function e_data_folder_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function e_result_folder_Callback(hObject, eventdata, handles)
function e_result_folder_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function e_prefix_Callback(hObject, eventdata, handles)
function e_prefix_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function e_xml_suffix_Callback(hObject, eventdata, handles)
function e_xml_suffix_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function e_spectral_channels_Callback(hObject, eventdata, handles)
function e_spectral_channels_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function e_coherence_pairs_Callback(hObject, eventdata, handles)
function e_coherence_pairs_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function e_ecg_channel_Callback(hObject, eventdata, handles)
function e_ecg_channel_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% =========================================================================
% MISSING CALLBACK FUNCTIONS - ADDED TO FIX ERRORS
% =========================================================================

function e_artifact_threshold_delta_Callback(hObject, eventdata, handles)
% Validate input is a single positive number
try
    deltaTh = str2double(get(hObject, 'String'));
    if isnan(deltaTh) || deltaTh <= 0
        errordlg('Please enter a positive number for delta threshold', 'Invalid Input');
        set(hObject, 'String', '2.5');
    end
catch
    errordlg('Please enter a valid number for delta threshold', 'Invalid Input');
    set(hObject, 'String', '2.5');
end

function e_artifact_threshold_delta_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function e_artifact_threshold_beta_Callback(hObject, eventdata, handles)
% Validate input is a single positive number
try
    betaTh = str2double(get(hObject, 'String'));
    if isnan(betaTh) || betaTh <= 0
        errordlg('Please enter a positive number for beta threshold', 'Invalid Input');
        set(hObject, 'String', '2.0');
    end
catch
    errordlg('Please enter a valid number for beta threshold', 'Invalid Input');
    set(hObject, 'String', '2.0');
end

function e_artifact_threshold_beta_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end