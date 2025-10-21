function uniformNames = ChannelMappingHelper(rawChannelNames)
% CHANNELMAPPINGHELPER Map various EEG/ECG channel naming conventions to uniform names

    uniformNames = rawChannelNames; % Initialize with original names
    
    % Define mapping from various conventions to uniform names
    mapping = {
        % Standard bipolar montage - EEG
        'C3-M2',    'C3-M2';
        'C4-M1',    'C4-M1'; 
        'F3-M2',    'F3-M2';
        'F4-M1',    'F4-M1';
        'O1-M2',    'O1-M2';
        'O2-M1',    'O2-M1';
        
        % A1/A2 reference montage - EEG
        'EEG C3-A2', 'C3-M2';
        'EEG C4-A1', 'C4-M1';
        'EEG F3-A2', 'F3-M2';
        'EEG F4-A1', 'F4-M1';
        'EEG O1-A2', 'O1-M2';
        'EEG O2-A1', 'O2-M1';
        
        % Other common EEG variations
        'C3A2',     'C3-M2';
        'C4A1',     'C4-M1';
        'F3A2',     'F3-M2';
        'F4A1',     'F4-M1';
        'O1A2',     'O1-M2';
        'O2A1',     'O2-M1';
        
        % With spaces/dashes variations - EEG
        'C3-A2',    'C3-M2';
        'C4-A1',    'C4-M1';
        'F3-A2',    'F3-M2';
        'F4-A1',    'F4-M1';
        'O1-A2',    'O1-M2';
        'O2-A1',    'O2-M1';
        
        % Simple EEG names (fallback) - BE MORE SPECIFIC
        'C3',       'C3-M2';
        'C4',       'C4-M1';
        'F3',       'F3-M2';
        'F4',       'F4-M1';
        'O1',       'O1-M2';
        'O2',       'O2-M1';
        
        % ECG CHANNEL MAPPING
        'RIP ECG',  'ECG';
        'ECG II',   'ECG';
        'ECG',      'ECG';
        'EKG',      'ECG';
        'ELECTROCARDIOGRAM', 'ECG';
        'ECG1',     'ECG';
        'ECG2',     'ECG';
        'EKG II',   'ECG';
        'EKG1',     'ECG';
        'EKG2',     'ECG';
        'DERIVATION II', 'ECG';
        'LEAD II',  'ECG';
        
        % ADD SpO2 SPECIFIC MAPPING TO PREVENT FALSE MATCHING
        'SpO2',     'SpO2';
        'SPO2',     'SpO2';
        'spo2',     'SpO2';
        'SaO2',     'SpO2';
        'sao2',     'SpO2';
    };

    % Apply mapping to each channel name
    for i = 1:length(rawChannelNames)
        rawName = strtrim(rawChannelNames{i});
        
        % Try exact match first
        found = false;
        for j = 1:size(mapping, 1)
            if strcmpi(rawName, mapping{j,1})
                uniformNames{i} = mapping{j,2};
                found = true;
                break;
            end
        end
        
        % If no exact match, use REGEX for more precise partial matching
        if ~found
            for j = 1:size(mapping, 1)
                % Use regex to match whole words or specific patterns
                pattern = ['(^|\s+)' regexptranslate('escape', mapping{j,1}) '(\s+|$|-)'];
                if ~isempty(regexpi(rawName, pattern))
                    uniformNames{i} = mapping{j,2};
                    found = true;
                    break;
                end
            end
        end
        
        % If still not found, keep original name
        if ~found
            uniformNames{i} = rawName;
        end
    end
    
    % Display mapping results
    fprintf('Channel name mapping:\n');
    for i = 1:length(rawChannelNames)
        if ~strcmp(rawChannelNames{i}, uniformNames{i})
            fprintf('  %s -> %s\n', rawChannelNames{i}, uniformNames{i});
        else
            fprintf('  %s (no mapping)\n', rawChannelNames{i});
        end
    end
end