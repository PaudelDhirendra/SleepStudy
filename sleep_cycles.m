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

% Merge short interruptions between REM periods (<15 epochs)
gaps = REMstart(2:end) - REMend(1:end-1);
for jj = 1:length(gaps)
    if gaps(jj) < 15*2  % 15 epochs (7.5 min at 30s epochs)
        hyp(REMend(jj):REMstart(jj+1)) = 5;
    end
end

% Re-find REM after merging
REMstart = find(hyp==5 & [0; diff(hyp)]>0);
REMend = find(hyp==5 & [diff(hyp); 0]<0);
if hyp(1)==5, REMstart = [1; REMstart]; end
if hyp(end)==5, REMend = [REMend; length(hyp)]; end

% Plot REM markers
hold on;
plot(REMstart, ones(size(REMstart)), '>g', 'MarkerSize', 8);
plot(REMend, ones(size(REMend)), '<m', 'MarkerSize', 8);
plot(hyp);
hold off;

% Enforce minimum REM duration (5 min) except first cycle
REMlength = REMend - REMstart;
norem = find(REMlength < 5*2);
norem(norem == 1) = []; % Skip first cycle
for jj = 1:length(norem)
    hyp(REMstart(norem(jj)):REMend(norem(jj))) = 1;
end

% Process wake periods
truewake = zeros(size(hyp));

% Beginning/end wake
if hyp(1)==0
    k = 1;
    while hyp(k)==0
        truewake(k) = 1;
        k = k+1;
    end
end

if hyp(end)==0
    k = length(hyp);
    while hyp(k)==0
        truewake(k) = 1;
        k = k-1;
    end
end

% Wake following REM
REMend = find(hyp==5 & [diff(hyp); 0]<0);
for j = 1:length(REMend)
    if REMend(j)+1 <= length(hyp) && hyp(REMend(j)+1)==0
        k = REMend(j)+1;
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

for jj = 1:length(wakestart)
    if wakeend(jj)-wakestart(jj)+1 >= 15*2
        truewake(wakestart(jj):wakeend(jj)) = 1;
    end
end

% Final stage assignment
hyp(hyp==0) = 1; % Other wake -> NREM
hyp(truewake==1) = 0; % True wake remains

% Plot final stages
plot(hyp);

% Identify sleep cycles
cycles = zeros(size(hyp));
NREMstart = find(hyp==1 & ([0; diff(hyp)]==1 | [0; diff(hyp)]==-4));
NREMend = find(hyp==1 & ([diff(hyp); 0]==-1 | [diff(hyp); 0]==4));

if hyp(1)==1, NREMstart = [1; NREMstart]; end
if hyp(end)==1, NREMend = [NREMend; length(hyp)]; end

% Plot cycle markers
hold on;
plot(NREMstart, ones(size(NREMstart)), '>c', 'MarkerSize', 8);
plot(NREMend, ones(size(NREMend)), '<r', 'MarkerSize', 8);
hold off;

% Assign cycle numbers
c = 1;
for jj = 1:length(NREMstart)
    % Check minimum NREM duration (15 min)
    if (NREMend(jj)-NREMstart(jj)+1 >= 15*2 && ...
       numel(find(hyp2(NREMstart(jj):NREMend(jj)))) >= 15*2)
        
        % Check for REM or wake termination
        if NREMend(jj)+1 <= length(hyp) && hyp(NREMend(jj)+1)==5 % REM termination
            k = 1;
            while NREMend(jj)+k <= length(hyp) && hyp(NREMend(jj)+k)==5
                k = k+1;
            end
            cycles(NREMstart(jj):NREMend(jj)+k-1) = c;
            c = c+1;
            
        elseif NREMend(jj)+1 <= length(hyp) && hyp(NREMend(jj)+1)==0 % Wake termination
            k = 1;
            while NREMend(jj)+k <= length(hyp) && hyp(NREMend(jj)+k)==0
                k = k+1;
            end
            if k > 15*2 || jj == length(NREMstart) % Long enough wake or last cycle
                cycles(NREMstart(jj):NREMend(jj)) = c;
                c = c+1;
            end
            
        elseif jj == length(NREMstart) % Last cycle
            cycles(NREMstart(jj):NREMend(jj)) = c;
            c = c+1;
        end
    end
end

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
end