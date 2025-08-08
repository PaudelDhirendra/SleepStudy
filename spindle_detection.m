function varargout = spindle_detection(varargin)
% [timespindles, durspindles, MINS, DENS, spindleStats] = spindle_detection(EDFfile, XMLfile, channels, references, just2, method, fspindle, ecglabel)
% Enhanced spindle detection that handles both unipolar and bipolar signals

% Set default parameter values
inputs = {'EDFfile', 'XMLfile', 'channels', 'references', 'just2', 'method', 'fspindle', 'ecglabel'};
outputs = {'timespindles', 'durspindles', 'MINS', 'DENS', 'spindleStats'};

% Parameter validation
Ninputs = length(inputs);
if nargin > Ninputs
    error('Too many input arguments');
end
if nargin < 6
    error('Not enough input arguments');
end

% Set defaults
fspindle = 13.5; % Default spindle center frequency
ecglabel = [];    % Default ECG label (auto-detect)

% Assign inputs
for n = 1:nargin
    eval([inputs{n} '= varargin{n};']);
end

% Output validation
Noutputs = length(outputs);
if nargout > Noutputs
    error('Too many output arguments');
end

%% Validate signal configuration
if isempty(references)
    fprintf('Processing Bipolar Montage (no reference specified)\n');
    isBipolar = false;
else
    if length(references) == 1
        fprintf('Processing Referential Montage with common reference: %s\n', references{1});
        isBipolar = true;
    elseif length(references) == length(channels)
        fprintf('Processing Referential Montage with channel-specific references\n');
        isBipolar = true;
    else
        error('Reference configuration mismatch. Must be empty, single reference, or one reference per channel');
    end
end

%% Initialize spindleStats structure
spindleStats = struct(...
    'amplitude', cell(length(channels), 1), ...
    'frequency', cell(length(channels), 1), ...
    'oscillations', cell(length(channels), 1), ...
    'N2_density', zeros(length(channels), 1), ...
    'N3_density', zeros(length(channels), 1), ...
    'cycle_density', [], ...
    'signal_type', repmat({'unipolar'}, length(channels), 1), ...
    'reference_used', repmat({''}, length(channels), 1));

if isBipolar
    for ch = 1:length(channels)
        if length(references) == 1
            spindleStats(ch).signal_type = 'bipolar';
            spindleStats(ch).reference_used = references{1};
        else
            spindleStats(ch).signal_type = 'bipolar';
            spindleStats(ch).reference_used = references{ch};
        end
    end
end

%% Preprocessing
try
    % Prepare signal list based on configuration
    if isBipolar
        if length(references) == 1
            signalList = [channels, references];
        else
            signalList = unique([channels, references]);
        end
    else
        signalList = channels;
    end
    
    stcStruct = struct(...
        'analysisDescription', 'Spindle Detection Analysis', ...
        'StudyEdfFileListResultsFn', '', ...
        'xlsFileContentCheckSummaryOut', '', ...
        'requiredSignals', signalList, ...
        'analysisSignals', channels, ...
        'referenceSignals', references, ...
        'StudySpectrumSummary', '', ...
        'StudyBandSummary', '', ...
        'StudyEdfDir', fileparts(EDFfile), ...
        'StudyEdfResultDir', fileparts(EDFfile), ...
        'checkFile', '', ...
        'denoiseEcg', ~isempty(ecglabel), ...
        'ecgName', ecglabel, ...
        'cycles_analysis', false);
    
    % Load EDF data
    edfObj = BlockEdfLoadClass(EDFfile, signalList);
    edfObj.numCompToLoad = 3;
    edfObj.SWAP_MIN_MAX = 1;
    edfObj = edfObj.blockEdfLoad;
    
    signalCell = edfObj.edf.signalCell;
    signalHeader = edfObj.edf.signalHeader;
    SR = unique([signalHeader.samples_in_record]);
    if length(SR) > 1
        error('Different sampling rates across channels');
    end
    
    % Create bipolar signals if needed
    if isBipolar
        fprintf('Creating bipolar derivations...\n');
        for ch = 1:length(channels)
            if length(references) == 1
                % Common reference for all channels
                refIdx = find(strcmpi(signalList, references{1}));
                if isempty(refIdx)
                    error('Reference channel %s not found in EDF', references{1});
                end
                signalCell{ch} = signalCell{ch} - signalCell{refIdx};
            else
                % Channel-specific references
                refIdx = find(strcmpi(signalList, references{ch}));
                if isempty(refIdx)
                    error('Reference channel %s for channel %s not found in EDF', references{ch}, channels{ch});
                end
                signalCell{ch} = signalCell{ch} - signalCell{refIdx};
            end
        end
    end
    
    % ECG decontamination if requested
    if ~isempty(ecglabel)
        try
            ecgObj = BlockEdfLoadClass(EDFfile, ecglabel);
            ecgObj = ecgObj.blockEdfLoad;
            ecgSignal = ecgObj.edf.signalCell{1};
            ecgSR = ecgObj.edf.signalHeader.samples_in_record;
            for ch = 1:length(channels)
                signalCell{ch} = ecgDecont(signalCell{ch}, SR, ecgSignal, ecgSR, channels{ch});
            end
        catch ME
            warning('ECG decontamination failed - proceeding without it: %s', ME.message);
        end
    end
    
    %% Load hypnogram
    try
        lcaObj = loadCompumedicsAnnotationsClass(XMLfile);
        lcaObj.scoreKey = { ...
            {'Awake', 0, 'W'}; {'1', 1, '1'}; {'2', 2, '2'}; ...
            {'3', 3, '3'}; {'4', 4, '4'}; {'REM', 5, 'R'}; ...
            {'X', 9, 'X'}; {'X', 10, 'X'}};
        lcaObj = lcaObj.loadFile;
        numericHypnogram = lcaObj.numericHypnogram;
        stage2Mask = numericHypnogram == 2;
        stage3Mask = numericHypnogram == 3;
    catch ME
        error('Hypnogram processing failed: %s', ME.message);
    end
    
    %% Spindle detection
    timespindles = cell(length(channels), 1);
    durspindles = cell(length(channels), 1);
    MINS = zeros(length(channels), 1);
    DENS = zeros(length(channels), 1);
    
    for ch = 1:length(channels)
        try
            sig = signalCell{ch};
            
            % Apply stage restriction if requested
            if just2
                hypExpanded = repelem(numericHypnogram, 30*SR);
                hypExpanded = hypExpanded(1:length(sig));
                sig(hypExpanded ~= 2) = NaN;
            end
            
            % Remove NaNs and prepare clean signal
            validIdx = ~isnan(sig);
            cleanSig = sig(validIdx);
            t = (1:length(sig))/SR;
            cleanT = t(validIdx);
            
            % Bandpass filter design
            bpFilt = designfilt('bandpassfir', ...
                'FilterOrder', 100, ...
                'CutoffFrequency1', 11, ...
                'CutoffFrequency2', 16, ...
                'SampleRate', SR);
            sigFilt = filtfilt(bpFilt, cleanSig);
            
            % RMS calculation
            windowSize = round(0.25 * SR);
            numWindows = floor(length(sigFilt)/windowSize);
            sigReshaped = reshape(sigFilt(1:numWindows*windowSize), windowSize, numWindows);
            sigRMS = rms(sigReshaped);
            
            % Threshold determination
            if just2
                stage2Idx = repelem(stage2Mask, 30*SR/windowSize);
                stage2Idx = stage2Idx(1:numWindows);
                thresh = prctile(sigRMS(stage2Idx), 95);
            else
                thresh = prctile(sigRMS, 95);
            end
            
            % Spindle detection
            spindleMask = sigRMS > thresh;
            diffMask = diff([0, spindleMask, 0]);
            starts = find(diffMask == 1);
            ends = find(diffMask == -1) - 1;
            durations = (ends - starts) * (windowSize/SR);
            
            % Duration criteria
            validSpindles = durations >= 0.5 & durations <= 3.0;
            starts = starts(validSpindles);
            ends = ends(validSpindles);
            durations = durations(validSpindles);
            
            % Merge close events
            i = 1;
            while i < length(starts)
                if (starts(i+1)*windowSize - ends(i)*windowSize)/SR < 1.0
                    ends(i) = ends(i+1);
                    durations(i) = (ends(i) - starts(i)) * (windowSize/SR);
                    starts(i+1) = [];
                    ends(i+1) = [];
                    durations(i+1) = [];
                else
                    i = i + 1;
                end
            end
            
            % Store spindle times and durations
            spindleTimes = starts * (windowSize/SR) + cleanT(1);
            spindleDurations = durations;
            
            % Calculate spindle metrics
            if ~isempty(starts)
                spindleStats.amplitude{ch} = zeros(length(starts), 1);
                spindleStats.frequency{ch} = zeros(length(starts), 1);
                spindleStats.oscillations{ch} = zeros(length(starts), 1);
                
                for s = 1:length(starts)
                    spindle_signal = sigFilt(starts(s):ends(s));
                    spindleStats.amplitude{ch}(s) = peak2peak(spindle_signal);
                    [~, locs] = findpeaks(spindle_signal, 'MinPeakHeight', 0.5*std(spindle_signal));
                    spindleStats.frequency{ch}(s) = length(locs) / durations(s);
                    spindleStats.oscillations{ch}(s) = length(locs);
                end
                
                % Calculate stage-specific densities
                N2_duration = max(sum(stage2Mask) * 30 / 60, 0.1);
                N3_duration = max(sum(stage3Mask) * 30 / 60, 0.1);
                spindleStats.N2_density(ch) = sum(ismember(round(spindleTimes/30), find(stage2Mask))) / N2_duration;
                spindleStats.N3_density(ch) = sum(ismember(round(spindleTimes/30), find(stage3Mask))) / N3_duration;
                
                % Calculate cycle-specific densities if available
                if exist('sleep_cycles', 'file')
                    try
                        cycles = sleep_cycles(numericHypnogram);
                        unique_cycles = unique(cycles(cycles > 0));
                        spindleStats.cycle_density{ch} = zeros(length(unique_cycles), 1);
                        for c = 1:length(unique_cycles)
                            cycle_mask = (cycles == unique_cycles(c));
                            cycle_duration = max(sum(cycle_mask) * 30 / 60, 0.1);
                            spindleStats.cycle_density{ch}(c) = sum(ismember(round(spindleTimes/30), find(cycle_mask))) / cycle_duration;
                        end
                    catch ME
                        warning('Cycle analysis failed: %s', ME.message);
                        spindleStats.cycle_density{ch} = [];
                    end
                else
                    spindleStats.cycle_density{ch} = [];
                end
            else
                spindleStats.N2_density(ch) = 0;
                spindleStats.N3_density(ch) = 0;
                spindleStats.cycle_density{ch} = [];
            end
            
            % Calculate analysis duration and density
            if just2
                analysisDuration = sum(stage2Mask) * 30 / 60;
            else
                analysisDuration = length(cleanSig)/SR / 60;
            end
            
            timespindles{ch} = spindleTimes;
            durspindles{ch} = spindleDurations;
            MINS(ch) = analysisDuration;
            DENS(ch) = length(spindleTimes) / analysisDuration;
            
        catch ME
            warning('Spindle detection failed for channel %s: %s', channels{ch}, ME.message);
            timespindles{ch} = [];
            durspindles{ch} = [];
            MINS(ch) = NaN;
            DENS(ch) = NaN;
            spindleStats.amplitude{ch} = [];
            spindleStats.frequency{ch} = [];
            spindleStats.oscillations{ch} = [];
            spindleStats.N2_density(ch) = NaN;
            spindleStats.N3_density(ch) = NaN;
            spindleStats.cycle_density{ch} = [];
        end
    end
    
catch ME
    error('Processing failed: %s', ME.message);
end

% Prepare outputs
for n = 1:nargout
    eval(['varargout{n} = ' outputs{n} ';']);
end
end