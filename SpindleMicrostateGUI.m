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

% Last Modified by GUIDE v2.5 21-Oct-2025 12:34:41

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
set(handles.e_spindle_channel, 'String', '{''C3-M2''}');
set(handles.e_microstate_channels, 'String', '{''F3-M2'',''F4-M1'',''C3-M2'',''C4-M1'',''O1-M2'',''O2-M1''}');
set(handles.e_ecg_name, 'String', '{''ECG''}');
set(handles.e_description_xml_suffix, 'String','.edf.xml');

% Disable run buttons
set(handles.pb_run_spindle, 'Enable', 'off');
set(handles.pb_run_microstate, 'Enable', 'off');
set(handles.pb_run_both, 'Enable', 'off');

% ECG off by default
set(handles.cb_ecg_artifact, 'Value', 0);
set(handles.e_ecg_name, 'Enable', 'off');

% Folder flags
handles.folderSeperator = '\';
handles.data_folder_path = pwd;
handles.data_folder_path_is_selected = 0;
handles.result_folder_path = pwd;
handles.result_folder_path_is_selected = 0;

% Microstate classes dropdown
set(handles.pm_microstate_classes, 'String', {'4','5','6'});
set(handles.pm_microstate_classes, 'Value', 1);

guidata(hObject, handles);

% This function has no output args, see OutputFcn.
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% varargin   command line arguments to SpindleMicrostateGUI (see VARARGIN)

% Choose default command line output for SpindleMicrostateGUI
handles.output = hObject;

% Update handles structure
guidata(hObject, handles);

% UIWAIT makes SpindleMicrostateGUI wait for user response (see UIRESUME)
% uiwait(handles.figure1);


% --- Outputs from this function are returned to the command line.
function varargout = SpindleMicrostateGUI_OutputFcn(hObject, eventdata, handles) 
% varargout  cell array for returning output args (see VARARGOUT);
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Get default command line output from handles structure
varargout{1} = handles.output;


% --- Executes on button press in pb_run_spindle.
function pb_run_spindle_Callback(hObject, eventdata, handles)
runAnalysis(handles, 'spindle');
% hObject    handle to pb_run_spindle (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)



function e_ecg_name_Callback(hObject, eventdata, handles)
% hObject    handle to e_ecg_name (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of e_ecg_name as text
%        str2double(get(hObject,'String')) returns contents of e_ecg_name as a double


% --- Executes during object creation, after setting all properties.
function e_ecg_name_CreateFcn(hObject, eventdata, handles)
% hObject    handle to e_ecg_name (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in cb_ecg_artifact.
function cb_ecg_artifact_Callback(hObject, eventdata, handles)
if get(hObject, 'Value')
    set(handles.e_ecg_name, 'Enable', 'on');
else
    set(handles.e_ecg_name, 'Enable', 'off');
end
% hObject    handle to cb_ecg_artifact (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of cb_ecg_artifact


% --- Executes on button press in checkbox3.
function checkbox3_Callback(hObject, eventdata, handles)
% hObject    handle to checkbox3 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of checkbox3


% --- Executes on button press in checkbox4.
function checkbox4_Callback(hObject, eventdata, handles)
% hObject    handle to checkbox4 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of checkbox4


% --- Executes on button press in pb_run_microstate.
function pb_run_microstate_Callback(hObject, eventdata, handles)
runAnalysis(handles, 'microstate');


% hObject    handle to pb_run_microstate (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)


% --- Executes on button press in pb_run_both.
function pb_run_both_Callback(hObject, eventdata, handles)
runAnalysis(handles, 'both');
% hObject    handle to pb_run_both (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)



function e_spindle_channel_Callback(hObject, eventdata, handles)
% hObject    handle to e_spindle_channel (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of e_spindle_channel as text
%        str2double(get(hObject,'String')) returns contents of e_spindle_channel as a double


% --- Executes during object creation, after setting all properties.
function e_spindle_channel_CreateFcn(hObject, eventdata, handles)
% hObject    handle to e_spindle_channel (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function e_microstate_channels_Callback(hObject, eventdata, handles)
% hObject    handle to e_microstate_channels (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of e_microstate_channels as text
%        str2double(get(hObject,'String')) returns contents of e_microstate_channels as a double


% --- Executes during object creation, after setting all properties.
function e_microstate_channels_CreateFcn(hObject, eventdata, handles)
% hObject    handle to e_microstate_channels (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on selection change in pm_microstate_classes.
function pm_microstate_classes_Callback(hObject, eventdata, handles)
% hObject    handle to pm_microstate_classes (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: contents = cellstr(get(hObject,'String')) returns pm_microstate_classes contents as cell array
%        contents{get(hObject,'Value')} returns selected item from pm_microstate_classes


% --- Executes during object creation, after setting all properties.
function pm_microstate_classes_CreateFcn(hObject, eventdata, handles)
% hObject    handle to pm_microstate_classes (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in pushbutton1.
function pushbutton1_Callback(hObject, eventdata, handles)
% hObject    handle to pushbutton1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)


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
% hObject    handle to pb_select_result (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)



function e_description_analysis_description_Callback(hObject, eventdata, handles)
% hObject    handle to e_description_analysis_description (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of e_description_analysis_description as text
%        str2double(get(hObject,'String')) returns contents of e_description_analysis_description as a double


% --- Executes during object creation, after setting all properties.
function e_description_analysis_description_CreateFcn(hObject, eventdata, handles)
% hObject    handle to e_description_analysis_description (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function e_prefix_Callback(hObject, eventdata, handles)
% hObject    handle to e_prefix (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of e_prefix as text
%        str2double(get(hObject,'String')) returns contents of e_prefix as a double


% --- Executes during object creation, after setting all properties.
function e_prefix_CreateFcn(hObject, eventdata, handles)
% hObject    handle to e_prefix (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function e_data_folder_Callback(hObject, eventdata, handles)
% hObject    handle to e_data_folder (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of e_data_folder as text
%        str2double(get(hObject,'String')) returns contents of e_data_folder as a double


% --- Executes during object creation, after setting all properties.
function e_data_folder_CreateFcn(hObject, eventdata, handles)
% hObject    handle to e_data_folder (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function e_result_folder_Callback(hObject, eventdata, handles)
% hObject    handle to e_result_folder (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of e_result_folder as text
%        str2double(get(hObject,'String')) returns contents of e_result_folder as a double


% --- Executes during object creation, after setting all properties.
function e_result_folder_CreateFcn(hObject, eventdata, handles)
% hObject    handle to e_result_folder (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function e_description_xml_suffix_Callback(hObject, eventdata, handles)
% hObject    handle to e_description_xml_suffix (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of e_description_xml_suffix as text
%        str2double(get(hObject,'String')) returns contents of e_description_xml_suffix as a double


% --- Executes during object creation, after setting all properties.
function e_description_xml_suffix_CreateFcn(hObject, eventdata, handles)
% Set file identification parameters

% hObject    handle to e_description_xml_suffix (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


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
% hObject    handle to pb_select_data (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
    function runAnalysis(handles, mode)
    dataDir = get(handles.e_data_folder, 'String');
    resultDir = get(handles.e_result_folder, 'String');
    prefix = get(handles.e_prefix, 'String');
    ecgName = eval(get(handles.e_ecg_name, 'String'));
    denoiseEcg = logical(get(handles.cb_ecg_artifact, 'Value'));
    nStates = str2double(get(handles.pm_microstate_classes, 'String'));
    xmlSuffix = get(handles.e_description_xml_suffix, 'String');

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
                % Correctly access the table data
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
                    % Try without suffix
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

         % Spindle Detection
if any(strcmp(mode, {'spindle','both'}))
    fprintf('Starting spindle detection...\n');
    try
        % Create parameters structure for spindle detection
        spindleParams = struct();
        spindleParams.resultFolder = subjectResultDir;
        spindleParams.outputPrefix = subPrefix;
        spindleParams.ecgName = ecgName{1};
        spindleParams.denoiseEcg = denoiseEcg;
        
        % Get XML file path (assuming it has same base name as EDF)
        [edfFolder, edfName, ~] = fileparts(edfPath);
        xmlPath = fullfile(edfFolder, [edfName '.XML']);
        
        % Check if XML file exists, if not try alternative naming
        if ~exist(xmlPath, 'file')
            xmlPath = fullfile(edfFolder, [edfName '.edf.XML']);
        end
        if ~exist(xmlPath, 'file')
            xmlPath = fullfile(edfFolder, [edfName '-edf.xml']);
        end
        
        % Create spindle detection object with correct constructor (3 arguments)
        spindleObj = SpindleDetectionClass(edfPath, xmlPath, spindleParams);
        
        % Run detection on specific channels
        channels = {'C3-M2', 'C4-M1'}; % Specify which channels to analyze
        spindleObj.runDetection(channels);
        
        % Save results with proper filename
        if ~isempty(spindleObj.spindleEvents)
            spindleFn = fullfile(subjectResultDir, [subPrefix '_Spindles.xlsx']);
            spindleObj.saveResults(spindleFn);
            spindleResults = spindleResults + 1;
            fprintf('SUCCESS: Detected %d spindles\n', size(spindleObj.spindleEvents, 1));
        else
            % Save empty results
            spindleFn = fullfile(subjectResultDir, [subPrefix '_Spindles.xlsx']);
            emptyTable = table({'No spindles detected'}, 'VariableNames', {'Result'});
            writetable(emptyTable, spindleFn);
            fprintf('No spindles detected (saved empty results)\n');
        end
    catch ME
        fprintf('Error in spindle detection: %s\n', ME.message);
        % Save error result
        spindleFn = fullfile(subjectResultDir, [subPrefix '_Spindles.xlsx']);
        errorTable = table({sprintf('Error: %s', ME.message)}, 'VariableNames', {'Result'});
        writetable(errorTable, spindleFn);
    end
end

            % Microstate Analysis
            % Get the SELECTED microstate classes (not all of them)
    classStrings = get(handles.pm_microstate_classes, 'String');
    selectedClass = get(handles.pm_microstate_classes, 'Value');
    nStates = str2double(classStrings{selectedClass});  % Use only the selected one
% Microstate Analysis
if any(strcmp(mode, {'microstate','both'}))
    fprintf('Starting microstate analysis...\n');
    try
        % Create parameters structure for microstate analysis
        microstateParams = struct();
        microstateParams.resultFolder = subjectResultDir;
        microstateParams.outputPrefix = subPrefix;
        microstateParams.numMaps = nStates;
        
        % Create microstate analysis object with correct constructor (2 arguments)
        microObj = MicrostateAnalysisClass(edfPath, microstateParams);
        microObj.runAnalysis();
        
        % Save results with proper filename
if ~isempty(microObj.microstateResults)
    % Save .mat file (for full data)
    microstateFn = fullfile(subjectResultDir, [subPrefix '_MicrostateResults.mat']);
    microObj.saveResults(microstateFn);
    
    % Save Excel file (for easy viewing)
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