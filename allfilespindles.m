function allfilespindles(datafolder, resultfolder, analysissignals, referencesignals, ...
                        referencemethod, only2, ecgname, fspin, start, xmlsuffix, spinmethod)
% ALLFILESPINDLES - Processes multiple EDF files for spindle detection
% Stores all results directly in resultfolder without subfolders

% Input validation
if nargin < 11
    error('Not enough input arguments');
end

% Handle reference method
if referencemethod == 1
    referencesignals = repmat(referencesignals, length(analysissignals), 1);
end

% Initialize variables
files = dir(fullfile(datafolder, '*.edf'));
files = files(start:end);
numFiles = length(files);
numChannels = length(analysissignals);

% Initialize results matrices
M = zeros(numFiles, numChannels); % Minutes of usable signal
D = zeros(numFiles, numChannels); % Spindle density
names = cell(numFiles, 1);

% Create main output folder if it doesn't exist
if ~exist(resultfolder, 'dir')
    mkdir(resultfolder);
end

% Process each file
for jj = 1:numFiles
    try
        % File paths
        EDFfile = fullfile(datafolder, files(jj).name);
        baseName = files(jj).name(1:end-4);
        names{jj} = baseName;
        XMLfile = fullfile(datafolder, [baseName xmlsuffix]);
        
        % Run spindle detection
        [timespindles, durspindles, MINS, DENS, spindleStats] = spindle_detection(...
            EDFfile, XMLfile, analysissignals, referencesignals, only2, ...
            spinmethod, fspin, ecgname);
        
        % Save results for this subject
        M(jj,:) = MINS;
        D(jj,:) = DENS;
        
        % Create individual Excel file directly in result folder
        subjectFn = fullfile(resultfolder, [baseName '_spindles.xlsx']);
        
        % Delete existing file if it exists
        if exist(subjectFn, 'file')
            delete(subjectFn);
        end
        
        % Write each channel to a separate sheet
        for ch = 1:numChannels
            sheetname = analysissignals{ch};
            if length(sheetname) > 31 % Excel sheet name limit
                sheetname = sheetname(1:31);
            end
            
            if ~isempty(timespindles{ch})
                % Write spindle events
                data = [timespindles{ch}(:), durspindles{ch}(:)];
                headers = {'Start Time (s)', 'Duration (s)'};
                xlswrite(subjectFn, headers, sheetname, 'A1');
                xlswrite(subjectFn, data, sheetname, 'A2');
                
                % Write summary metrics
                summary = {
                    'Channel:', analysissignals{ch};
                    'Total Spindles:', length(timespindles{ch});
                    'Density (spindles/min):', DENS(ch);
                    'N2 Density:', spindleStats.N2_density(ch);
                    'N3 Density:', spindleStats.N3_density(ch);
                    'Mean Duration (s):', mean(durspindles{ch});
                    'Mean Amplitude (µV):', mean(spindleStats.amplitude{ch});
                    'Mean Frequency (Hz):', mean(spindleStats.frequency{ch});
                    'Mean Oscillations:', mean(spindleStats.oscillations{ch});
                    };
                xlswrite(subjectFn, summary, sheetname, 'D1');
                
                % Write cycle densities if available
                if isfield(spindleStats, 'cycle_density') && ~isempty(spindleStats.cycle_density{ch})
                    cycle_summary = [{'Cycle', 'Density'}; ...
                                    num2cell([(1:length(spindleStats.cycle_density{ch}))', ...
                                              spindleStats.cycle_density{ch}(:)])];
                    xlswrite(subjectFn, cycle_summary, sheetname, 'D10');
                end
            else
                xlswrite(subjectFn, {'No spindles detected'}, sheetname, 'A1');
            end
        end
        
        fprintf('Processed file %d/%d: %s\n', jj, numFiles, baseName);
        
    catch ME
        warning('Error processing file %s: %s', files(jj).name, ME.message);
        M(jj,:) = NaN(1,numChannels);
        D(jj,:) = NaN(1,numChannels);
    end
end

% Save summary across all subjects
summaryFn = fullfile(resultfolder, 'spindle_summary.xlsx');
if exist(summaryFn, 'file')
    delete(summaryFn);
end

% Prepare summary data
summaryData = cell(numFiles + 2, numChannels * 2 + 1);

% Create headers
summaryData{1,1} = 'Subject';
for ch = 1:numChannels
    summaryData{1, ch*2} = [analysissignals{ch} ' (min)'];
    summaryData{1, ch*2+1} = [analysissignals{ch} ' (dens)'];
end

% Add data rows
for jj = 1:numFiles
    summaryData{jj+2,1} = names{jj};
    for ch = 1:numChannels
        summaryData{jj+2, ch*2} = M(jj,ch);
        summaryData{jj+2, ch*2+1} = D(jj,ch);
    end
end

% Add column headers for data
summaryData{2,1} = '';
for ch = 1:numChannels
    summaryData{2, ch*2} = 'Analysis Duration';
    summaryData{2, ch*2+1} = 'Spindle Density';
end

% Write summary file
xlswrite(summaryFn, summaryData);

fprintf('\nProcessing complete. Results saved to:\n%s\n', resultfolder);
end