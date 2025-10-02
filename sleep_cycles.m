function cycles = sleep_cycles(hyp, varargin)
% SLEEP_CYCLES - Identify sleep cycles from hypnogram
%   cycles = sleep_cycles(hyp) - processes hypnogram vector
% Optional params:
%   'Visible' - true/false to show figure (default false)
%   'SaveFig' - filename to save figure (default '')

% Parse optional parameters
p = inputParser;
addOptional(p, 'Visible', false, @islogical);
addOptional(p, 'SaveFig', '', @ischar);
parse(p, varargin{:});

% Create figure with specified visibility
hFig = figure('Visible', p.Results.Visible);
set(hFig, 'NumberTitle', 'off', 'Name', 'Sleep Cycle Analysis');

hyp2 = hyp; % Keep original hypnogram

% Plot original hypnogram
ax(1) = subplot(311);
plot(hyp);
title('Original Hypnogram');
ylabel('Sleep Stage');

% Convert stages: N1 becomes wake, N2-N4 become NREM
ax(2) = subplot(312);
hyp(hyp==1) = 0;    % N1 -> Wake
hyp(hyp>1 & hyp<5) = 1; % N2-N4 -> NREM (1)
plot(hyp);
title('Processed Stages');
ylabel('Simplified Stage');
linkaxes(ax, 'x');

% Process REM periods
REMstart = find(hyp==5 & [0; diff(hyp)]>0);
REMend = find(hyp==5 & [diff(hyp); 0]<0);

% Handle edge cases
if hyp(1)==5, REMstart = [1; REMstart]; end
if hyp(end)==5, REMend = [REMend; length(hyp)]; end

% FIXED: Check array lengths before gap calculation
if ~isempty(REMstart) && ~isempty(REMend) && length(REMstart) == length(REMend)
    % Only calculate gaps if we have matching pairs and multiple periods
    if length(REMstart) > 1
        gaps = REMstart(2:end) - REMend(1:end-1);
        for jj = 1:length(gaps)
            if gaps(jj) < 15*2  % 15 epochs (7.5 min at 30s epochs)
                hyp(REMend(jj):REMstart(jj+1)) = 5;
            end
        end
    end
else
    % If arrays don't match, try to pair them properly
    if ~isempty(REMstart) && ~isempty(REMend)
        % Find the minimum length and use only matching pairs
        min_len = min(length(REMstart), length(REMend));
        if min_len > 1
            REMstart_temp = REMstart(1:min_len);
            REMend_temp = REMend(1:min_len);
            gaps = REMstart_temp(2:end) - REMend_temp(1:end-1);
            for jj = 1:length(gaps)
                if gaps(jj) < 15*2
                    hyp(REMend_temp(jj):REMstart_temp(jj+1)) = 5;
                end
            end
        end
    end
end

% Re-find REM after merging
REMstart = find(hyp==5 & [0; diff(hyp)]>0);
REMend = find(hyp==5 & [diff(hyp); 0]<0);
if hyp(1)==5, REMstart = [1; REMstart]; end
if hyp(end)==5, REMend = [REMend; length(hyp)]; end

% Plot REM markers
hold on;
if ~isempty(REMstart)
    plot(REMstart, ones(size(REMstart)), '>g', 'MarkerSize', 8);
end
if ~isempty(REMend)
    plot(REMend, ones(size(REMend)), '<m', 'MarkerSize', 8);
end
plot(hyp);
hold off;

% Enforce minimum REM duration (5 min) except first cycle
if ~isempty(REMstart) && ~isempty(REMend)
    % Match array lengths
    min_len = min(length(REMstart), length(REMend));
    REMstart = REMstart(1:min_len);
    REMend = REMend(1:min_len);
    
    REMlength = REMend - REMstart;
    norem = find(REMlength < 5*2);
    norem(norem == 1) = []; % Skip first cycle
    for jj = 1:length(norem)
        if norem(jj) <= length(REMstart)
            hyp(REMstart(norem(jj)):REMend(norem(jj))) = 1;
        end
    end
end

% Process wake periods
truewake = zeros(size(hyp));

% Beginning/end wake
if hyp(1)==0
    k = 1;
    while k <= length(hyp) && hyp(k)==0
        truewake(k) = 1;
        k = k+1;
    end
end

if hyp(end)==0
    k = length(hyp);
    while k >= 1 && hyp(k)==0
        truewake(k) = 1;
        k = k-1;
    end
end

% Wake following REM
REMend_temp = find(hyp==5 & [diff(hyp); 0]<0);
for j = 1:length(REMend_temp)
    if REMend_temp(j)+1 <= length(hyp) && hyp(REMend_temp(j)+1)==0
        k = REMend_temp(j)+1;
        while k <= length(hyp) && hyp(k)==0
            truewake(k) = 1;
            k = k+1;
        end
    end
end

% Long wake bouts (>15 min)
wakestart = find(hyp==0 & [0; diff(hyp)]<0);
wakeend = find(hyp==0 & [diff(hyp); 0]>0);
if hyp(1)==0, wakestart = [1; wakestart]; end
if hyp(end)==0, wakeend = [wakeend; length(hyp)]; end

if ~isempty(wakestart) && ~isempty(wakeend)
    % Match lengths
    min_len = min(length(wakestart), length(wakeend));
    wakestart = wakestart(1:min_len);
    wakeend = wakeend(1:min_len);
    
    for jj = 1:min_len
        if wakeend(jj)-wakestart(jj)+1 >= 15*2
            truewake(wakestart(jj):wakeend(jj)) = 1;
        end
    end
end

% Final stage assignment
hyp(hyp==0) = 1; % Other wake -> NREM
hyp(truewake==1) = 0; % True wake remains

% Plot final stages
plot(hyp);

% Identify sleep cycles - FIXED LOGIC
cycles = zeros(size(hyp));

% Find all NREM periods that meet minimum duration
NREM_periods = [];
nrem_start = find(hyp==1 & [1; diff(hyp)] ~= 0);
nrem_end = find(hyp==1 & [diff(hyp); 1] ~= 0);

% Filter for minimum duration (15 min)
for i = 1:length(nrem_start)
    if (nrem_end(i) - nrem_start(i) + 1) >= 15*2
        NREM_periods = [NREM_periods; nrem_start(i), nrem_end(i)];
    end
end

% Assign cycles with proper termination logic
c = 1;
for i = 1:size(NREM_periods, 1)
    nrem_start = NREM_periods(i, 1);
    nrem_end = NREM_periods(i, 2);
    
    % Skip if this NREM is already assigned
    if any(cycles(nrem_start:nrem_end) > 0)
        continue;
    end
    
    % Find the end of this cycle
    cycle_end = find_cycle_end(hyp, nrem_end, i == size(NREM_periods, 1));
    
    % Assign cycle number
    cycles(nrem_start:cycle_end) = c;
    c = c + 1;
end

% Plot cycle markers
hold on;
for i = 1:size(NREM_periods, 1)
    plot([NREM_periods(i, 1) NREM_periods(i, 1)], [0 1], 'c--', 'LineWidth', 2);
    cycle_end = find(cycles == i, 1, 'last');
    if ~isempty(cycle_end)
        plot([cycle_end cycle_end], [0 1], 'r--', 'LineWidth', 2);
    end
end
hold off;

% Plot final cycles
ax(3) = subplot(313);
plot(cycles);
title('Identified Sleep Cycles');
ylabel('Cycle Number');
xlabel('Epoch Number');
linkaxes(ax, 'x');

% Save figure if requested
if ~isempty(p.Results.SaveFig)
    saveas(hFig, p.Results.SaveFig);
    fprintf('Saved figure to: %s\n', p.Results.SaveFig);
end

% Close figure unless visibility was requested
if ~p.Results.Visible
    close(hFig);
end

fprintf('Identified %d sleep cycles\n', c-1);
end

%% Helper function to find cycle end
function cycle_end = find_cycle_end(hyp, nrem_end, is_last_cycle)
% Find the appropriate end point for a sleep cycle

    cycle_end = nrem_end; % Default to end of NREM
    
    % Look ahead to find termination
    idx = nrem_end + 1;
    while idx <= length(hyp)
        current_stage = hyp(idx);
        
        if current_stage == 5 % REM sleep
            % Include REM period in cycle
            while idx <= length(hyp) && hyp(idx) == 5
                idx = idx + 1;
            end
            cycle_end = idx - 1;
            
        elseif current_stage == 0 % Wake/N1
            % Check if this is termination wake
            wake_start = idx;
            wake_end = wake_start;
            
            % Find the complete wake period
            while wake_end < length(hyp) && hyp(wake_end + 1) == 0
                wake_end = wake_end + 1;
            end
            
            wake_duration = wake_end - wake_start + 1;
            
            if wake_duration >= 15*2 % Long wake terminates cycle
                cycle_end = wake_start - 1; % End before wake
                break;
            else
                % Brief awakening - continue through it
                idx = wake_end + 1;
                cycle_end = wake_end; % Include brief wake in cycle
            end
            
        elseif current_stage == 1 % New NREM - starts new cycle
            cycle_end = idx - 1;
            break;
            
        else
            idx = idx + 1;
        end
        
        if idx > length(hyp)
            cycle_end = length(hyp);
            break;
        end
    end
    
    % For last cycle, ensure we go to end of recording if appropriate
    if is_last_cycle && cycle_end < length(hyp)
        % Check if what follows is sleep (not long wake)
        remaining_stages = hyp(cycle_end+1:end);
        if all(remaining_stages ~= 0) || ...
           (any(remaining_stages == 0) && length(find(remaining_stages == 0)) < 15*2)
            cycle_end = length(hyp);
        end
    end
end