function varargout = SpindleMicrostateGUI(varargin)
% SPINDLEMICROSTATEGUI MATLAB code for SpindleMicrostateGUI.fig
%      SPINDLEMICROSTATEGUI, by itself, creates a new SPINDLEMICROSTATEGUI or raises the existing
%      singleton*.
%
%      H = SPINDLEMICROSTATEGUI returns the handle to a new SPINDLEMICROSTATEGUI or the handle to
%      the existing singleton*.
%
%      SPINDLEMICROSTATEGUI('CALLBACK',hObject,eventData,handles,...) calls the local
%      function named CALLBACK in SPINDLEMICROSTATEGUI.M with the given input arguments.
%
%      SPINDLEMICROSTATEGUI('Property','Value',...) creates a new SPINDLEMICROSTATEGUI or raises the
%      existing singleton*.  Starting from the left, property value pairs are
%      applied to the GUI before SpindleMicrostateGUI_OpeningFcn gets called.  An
%      unrecognized property name or invalid value makes property application
%      stop.  All inputs are passed to SpindleMicrostateGUI_OpeningFcn via varargin.
%
%      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
%      instance to run (singleton)".
%
% See also: GUIDE, GUIDATA, GUIHANDLES

% Edit the above text to modify the response to help SpindleMicrostateGUI

% Last Modified by GUIDE v2.5 22-Oct-2025 01:07:28

% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @SpindleMicrostateGUI_OpeningFcn, ...
                   'gui_OutputFcn',  @SpindleMicrostateGUI_OutputFcn, ...
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


% --- Executes just before SpindleMicrostateGUI is made visible.
function SpindleMicrostateGUI_OpeningFcn(hObject, eventdata, handles, varargin)
handles.output = hObject;

% Set defaults
set(handles.e_description_analysis_description, 'String','Spindle Microstate Analysis');
set(handles.e_prefix, 'String', 'study__');

% AUTO-SELECT: These will be populated when files are processed
set(handles.e_spindle_channel, 'String', '{''Auto-Select''}');
set(handles.e_microstate_channels, 'String', '{''Auto-Select''}');
set(handles.e_ecg_channels, 'String', '{''Auto-Select''}');

set(handles.e_description_xml_suffix, 'String','.edf.xml');

% Set defaults for artifact detection controls
set(handles.cb_ecg_decontamination, 'Value', 1);
set(handles.e_ecg_channels, 'Enable', 'off');
set(handles.cb_artifact_detection, 'Value', 1);
set(handles.e_artifact_threshold_delta, 'String', '2.5');
set(handles.e_artifact_threshold_delta, 'Enable', 'on');
set(handles.e_artifact_threshold_beta, 'String', '2.0');
set(handles.e_artifact_threshold_beta, 'Enable', 'on');

% Disable run buttons
set(handles.pb_run_spindle, 'Enable', 'off');
set(handles.pb_run_microstate, 'Enable', 'off');
set(handles.pb_run_both, 'Enable', 'off');

% Folder flags
handles.folderSeperator = '\';
handles.data_folder_path = pwd;
handles.data_folder_path_is_selected = 0;
handles.result_folder_path = pwd;
handles.result_folder_path_is_selected = 0;

% Microstate classes dropdown
set(handles.pm_microstate_classes, 'String', {'4','5','6'});
set(handles.pm_microstate_classes, 'Value', 1);

% Update handles structure
guidata(hObject, handles);

% UIWAIT makes SpindleMicrostateGUI wait for user response (see UIRESUME)
% uiwait(handles.figure1);


% --- Outputs from this function are returned to the command line.
function varargout = SpindleMicrostateGUI_OutputFcn(hObject, eventdata, handles) 
varargout{1} = handles.output;


% --- Executes on button press in pb_run_spindle.
function pb_run_spindle_Callback(hObject, eventdata, handles)
runAnalysis(handles, 'spindle');


% --- Executes on button press in pb_run_microstate.
function pb_run_microstate_Callback(hObject, eventdata, handles)
runAnalysis(handles, 'microstate');


% --- Executes on button press in pb_run_both.
function pb_run_both_Callback(hObject, eventdata, handles)
runAnalysis(handles, 'both');


% --- Executes on button press in pb_select_data.
function pb_select_data_Callback(hObject, eventdata, handles)
data_folder_path = handles.data_folder_path;
dialogTitle = 'Select Data Folder';
[folder_path, folder_is_selected] = pb_select_data_folder(data_folder_path, dialogTitle);
if folder_is_selected == 1
    set(handles.e_data_folder, 'String', folder_path);
    handles.data_folder_path = folder_path;
    handles.data_folder_path_is_selected = folder_is_selected;
    guidata(hObject, handles);
    if handles.data_folder_path_is_selected && handles.result_folder_path_is_selected
        set(handles.pb_run_spindle, 'Enable', 'on');
        set(handles.pb_run_microstate, 'Enable', 'on');
        set(handles.pb_run_both, 'Enable', 'on');
    end
end


% --- Executes on button press in pb_select_result.
function pb_select_result_Callback(hObject, eventdata, handles)
result_folder_path = handles.result_folder_path;
dialogTitle = 'Select Result Folder';
[folder_path, folder_is_selected] = pb_select_data_folder(result_folder_path, dialogTitle);
if folder_is_selected == 1
    set(handles.e_result_folder, 'String', folder_path);
    handles.result_folder_path = folder_path;
    handles.result_folder_path_is_selected = folder_is_selected;
    guidata(hObject, handles);
    if handles.data_folder_path_is_selected && handles.result_folder_path_is_selected
        set(handles.pb_run_spindle, 'Enable', 'on');
        set(handles.pb_run_microstate, 'Enable', 'on');
        set(handles.pb_run_both, 'Enable', 'on');
    end
end


% --- Executes on button press in cb_ecg_decontamination.
function cb_ecg_decontamination_Callback(hObject, eventdata, handles)
if get(hObject, 'Value')
    set(handles.e_ecg_channels, 'Enable', 'on');
else
    set(handles.e_ecg_channels, 'Enable', 'off');
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


function e_description_analysis_description_Callback(hObject, eventdata, handles)


function e_description_analysis_description_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


function e_prefix_Callback(hObject, eventdata, handles)


function e_prefix_CreateFcn(hObject, eventdata, handles)
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


function e_description_xml_suffix_Callback(hObject, eventdata, handles)


function e_description_xml_suffix_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


function e_spindle_channel_Callback(hObject, eventdata, handles)


function e_spindle_channel_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


function e_microstate_channels_Callback(hObject, eventdata, handles)


function e_microstate_channels_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


function e_ecg_channels_Callback(hObject, eventdata, handles)


function e_ecg_channels_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


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


% --- Executes on selection change in pm_microstate_classes.
function pm_microstate_classes_Callback(hObject, eventdata, handles)


function pm_microstate_classes_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in pushbutton1.
function pushbutton1_Callback(hObject, eventdata, handles)


% --- Executes on button press in checkbox3.
function checkbox3_Callback(hObject, eventdata, handles)


% --- Executes on button press in checkbox4.
function checkbox4_Callback(hObject, eventdata, handles)


% =========================================================================
% CUSTOM FUNCTIONS
% =========================================================================
function [spindleChannels, microstateChannels, ecgChannels] = detectAvailableChannels(edfPath)
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
        
        % Detect spindle channels (prefer C3-M2, C4-M1)
        spindleChannels = detectSpindleChannels(mappedNames);
        
        % Detect microstate channels (standard 6 bipolar)
        microstateChannels = detectMicrostateChannels(mappedNames);
        
        % Detect ECG channels
        ecgChannels = detectECGChannels(mappedNames);
        
        fprintf('Auto-detected:\n');
        fprintf('  Spindle channels: %s\n', strjoin(spindleChannels, ', '));
        fprintf('  Microstate channels: %s\n', strjoin(microstateChannels, ', '));
        fprintf('  ECG channels: %s\n', strjoin(ecgChannels, ', '));
        
    catch ME
        fprintf('Error auto-detecting channels: %s\n', ME.message);
        % Fallback to defaults
        spindleChannels = {'C3-M2'};
        microstateChannels = {'F3-M2', 'F4-M1', 'C3-M2', 'C4-M1', 'O1-M2', 'O2-M1'};
        ecgChannels = {'ECG', 'EKG'};
    end


function spindleChannels = detectSpindleChannels(channelNames)
    % Prefer C3-M2, C4-M1 for spindle detection
    preferredSpindle = {'C3-M2', 'C4-M1'};
    spindleChannels = {};
    
    for i = 1:length(preferredSpindle)
        if any(strcmp(channelNames, preferredSpindle{i}))
            spindleChannels{end+1} = preferredSpindle{i};
        end
    end
    
    % Fallback: any C3 or C4 channels
    if isempty(spindleChannels)
        for i = 1:length(channelNames)
            if contains(upper(channelNames{i}), 'C3') || contains(upper(channelNames{i}), 'C4')
                spindleChannels{end+1} = channelNames{i};
            end
        end
    end
    
    % Final fallback: use first available EEG channel
    if isempty(spindleChannels) && ~isempty(channelNames)
        spindleChannels = {channelNames{1}};
    end


function microstateChannels = detectMicrostateChannels(channelNames)
    % Standard 6 bipolar channels for microstate analysis
    standardMicrostate = {'F3-M2', 'F4-M1', 'C3-M2', 'C4-M1', 'O1-M2', 'O2-M1'};
    microstateChannels = {};
    
    for i = 1:length(standardMicrostate)
        if any(strcmp(channelNames, standardMicrostate{i}))
            microstateChannels{end+1} = standardMicrostate{i};
        end
    end
    
    % Fallback: look for individual electrode names
    if length(microstateChannels) < 4
        eegElectrodes = {'F3', 'F4', 'C3', 'C4', 'O1', 'O2', 'FZ', 'CZ', 'PZ', 'FP1', 'FP2'};
        foundChannels = {};
        
        for i = 1:length(channelNames)
            for j = 1:length(eegElectrodes)
                if contains(upper(channelNames{i}), upper(eegElectrodes{j}))
                    foundChannels{end+1} = channelNames{i};
                    break;
                end
            end
        end
        
        % Use up to 6 EEG channels
        if length(foundChannels) > 6
            microstateChannels = foundChannels(1:6);
        else
            microstateChannels = foundChannels;
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


    function runAnalysis(handles, mode)
    dataDir = get(handles.e_data_folder, 'String');
    resultDir = get(handles.e_result_folder, 'String');
    prefix = get(handles.e_prefix, 'String');
    xmlSuffix = get(handles.e_description_xml_suffix, 'String');

    % Get the parameters from GUI
    denoiseEcg = logical(get(handles.cb_ecg_decontamination, 'Value'));
    enableArtifactDetection = logical(get(handles.cb_artifact_detection, 'Value'));
    
    % Get thresholds from two separate boxes
    deltaTh = str2double(get(handles.e_artifact_threshold_delta, 'String'));
    betaTh = str2double(get(handles.e_artifact_threshold_beta, 'String'));
    artifactThresholds = [deltaTh, betaTh];
    
    % Validate thresholds
    if isnan(deltaTh) || isnan(betaTh) || deltaTh <= 0 || betaTh <= 0
        errordlg('Invalid artifact thresholds. Using defaults [2.5, 2.0].', 'Invalid Thresholds');
        artifactThresholds = [2.5, 2.0];
    end
    
    fprintf('\n=== STARTING ANALYSIS ===\n');
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
    spindleResults = 0;
    microstateResults = 0;
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
            [autoSpindleChannels, autoMicrostateChannels, autoEcgChannels] = detectAvailableChannels(edfPath);
            
            % Update GUI with detected channels (for display only)
            if k == 1 % Only update GUI once with first file's channels
                set(handles.e_spindle_channel, 'String', ['{', sprintf('''%s'',', autoSpindleChannels{1:end-1}), '''', autoSpindleChannels{end}, '''}']);
                set(handles.e_microstate_channels, 'String', ['{', sprintf('''%s'',', autoMicrostateChannels{1:end-1}), '''', autoMicrostateChannels{end}, '''}']);
                set(handles.e_ecg_channels, 'String', ['{', sprintf('''%s'',', autoEcgChannels{1:end-1}), '''', autoEcgChannels{end}, '''}']);
                guidata(handles.figure1, handles);
            end
            
            % Create parameters structure with auto-detected channels
            analysisParams = struct();
            analysisParams.denoiseEcg = denoiseEcg;
            analysisParams.ecgName = autoEcgChannels;
            analysisParams.enableArtifactDetection = enableArtifactDetection;
            analysisParams.artifactThreshold = artifactThresholds;
            analysisParams.autoSpindleChannels = autoSpindleChannels;
            analysisParams.autoMicrostateChannels = autoMicrostateChannels;
            
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

            % Spindle Detection with auto-detected channels
            if any(strcmp(mode, {'spindle','both'}))
                fprintf('Starting spindle detection with auto-selected channels: %s\n', strjoin(autoSpindleChannels, ', '));
                try
                    % Create parameters structure for spindle detection
                    spindleParams = struct();
                    spindleParams.resultFolder = subjectResultDir;
                    spindleParams.outputPrefix = subPrefix;
                    spindleParams.denoiseEcg = analysisParams.denoiseEcg;
                    spindleParams.ecgName = analysisParams.ecgName;
                    spindleParams.enableArtifactDetection = analysisParams.enableArtifactDetection;
                    spindleParams.artifactThreshold = analysisParams.artifactThreshold;
                    
                    % Get XML file path
                    [edfFolder, edfName, ~] = fileparts(edfPath);
                    xmlPath = fullfile(edfFolder, [edfName '.XML']);
                    
                    % Check if XML file exists, if not try alternative naming
                    if ~exist(xmlPath, 'file')
                        xmlPath = fullfile(edfFolder, [edfName '.edf.XML']);
                    end
                    if ~exist(xmlPath, 'file')
                        xmlPath = fullfile(edfFolder, [edfName '-edf.xml']);
                    end
                    
                    % Create spindle detection object
                    spindleObj = SpindleDetectionClass(edfPath, xmlPath, spindleParams);
                    
                    % Run detection on auto-detected channels
                    spindleObj.runDetection(autoSpindleChannels);
                    
                    % Save results
                    if ~isempty(spindleObj.spindleEvents)
                        spindleFn = fullfile(subjectResultDir, [subPrefix '_Spindles.xlsx']);
                        spindleObj.saveResults(spindleFn);
                        spindleResults = spindleResults + 1;
                        fprintf('SUCCESS: Detected %d spindles\n', size(spindleObj.spindleEvents, 1));
                    else
                        spindleFn = fullfile(subjectResultDir, [subPrefix '_Spindles.xlsx']);
                        emptyTable = table({'No spindles detected'}, 'VariableNames', {'Result'});
                        writetable(emptyTable, spindleFn);
                        fprintf('No spindles detected (saved empty results)\n');
                    end
                catch ME
                    fprintf('Error in spindle detection: %s\n', ME.message);
                    spindleFn = fullfile(subjectResultDir, [subPrefix '_Spindles.xlsx']);
                    errorTable = table({sprintf('Error: %s', ME.message)}, 'VariableNames', {'Result'});
                    writetable(errorTable, spindleFn);
                end
            end

            % Microstate Analysis with auto-detected channels
            if any(strcmp(mode, {'microstate','both'}))
                fprintf('Starting microstate analysis with auto-selected channels: %s\n', strjoin(autoMicrostateChannels, ', '));
                try
                    % Get the SELECTED microstate classes
                    classStrings = get(handles.pm_microstate_classes, 'String');
                    selectedClass = get(handles.pm_microstate_classes, 'Value');
                    nStates = str2double(classStrings{selectedClass});
                    
                    % Create parameters structure for microstate analysis
                    microstateParams = struct();
                    microstateParams.resultFolder = subjectResultDir;
                    microstateParams.outputPrefix = subPrefix;
                    microstateParams.numMaps = nStates;
                    microstateParams.denoiseEcg = analysisParams.denoiseEcg;
                    microstateParams.ecgName = analysisParams.ecgName;
                    microstateParams.enableArtifactDetection = analysisParams.enableArtifactDetection;
                    microstateParams.artifactThreshold = analysisParams.artifactThreshold;
                    microstateParams.preferredChannels = autoMicrostateChannels; % Pass auto-detected channels
                    
                    % Create microstate analysis object
                    microObj = MicrostateAnalysisClass(edfPath, microstateParams);
                    microObj.runAnalysis();
                    
                    % Save results
                    if ~isempty(microObj.microstateResults)
                        microstateFn = fullfile(subjectResultDir, [subPrefix '_MicrostateResults.mat']);
                        microObj.saveResults(microstateFn);
                        
                        microstateExcelFn = fullfile(subjectResultDir, [subPrefix '_MicrostateResults.xlsx']);
                        microObj.saveResultsToExcel(microstateExcelFn);
                        
                        microstateResults = microstateResults + 1;
                        fprintf('SUCCESS: Generated microstate results\n');
                    end
                catch ME
                    fprintf('Error in microstate analysis: %s\n', ME.message);
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
                           'Successful spindle analyses: %d\n' ...
                           'Successful microstate analyses: %d\n' ...
                           'Errors encountered: %d'], ...
                           n, processedFiles, spindleResults, microstateResults, length(errors));
    
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
    fprintf('Spindle results: %d\n', spindleResults);
    fprintf('Microstate results: %d\n', microstateResults);
    fprintf('Errors: %d\n', length(errors));
    fprintf('========================\n');
    
    msgbox(resultMessage, 'Analysis Complete');


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
