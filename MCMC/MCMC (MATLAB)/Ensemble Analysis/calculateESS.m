% Computes the effective sample size from
% the monotone sequence estimator from Geyer (1992)
% ensemble is the set of posterior samples
% Implementation follows from Calderhead's example
% returns a vector that holds the effective sample size for
% each parameter
% Time normalizes result if isTimeNormalized is true
% The basic idea is to preprocess the autocorrelation so 
% it monotonically decreases, then sum up the components
% until the first component that hits zero. The smaller the
% sum the larger the effective sample size is

function [minESS, meanESS,...
          maxESS, totalESS]  = calculateESS(ensemble)
      
maxLags           = ensemble.autoCorr.maxLags;
isTimeNormalized  = ensemble.ESS.isTimeNormalized;
posteriorTime     = ensemble.posteriorTime;
samples           = ensemble.samples;
% ensemble is a numSamples x numParams matrix

[numSamples, numParams] = size(samples);

% autocorrelation of each parameter
%auto_corrs = zeros(numSamples, numParams);
for i = 1: numParams
    auto_corrs(:, i) =  autocorr(samples(:, i), maxLags); 
end

half_autoCorr_length = floor(size(auto_corrs, 1) / 2);

% Gammas is the initial sequence estimator
Gammas    = zeros(half_autoCorr_length, numParams);

% Calculate Gammas from the autocorrelations
% Bin autocorrelations together in groups of 2
for i = 1: numParams    
    % Add other Gammas
    for j = 1: half_autoCorr_length
        Gammas(j,i) = auto_corrs(2*j - 1, i) + ...
                      auto_corrs(2*j, i);
    end
end

% Calculate the initial monotone convergence estimator
% -> Gammas(j,i) is min of preceding values
% Computes a running minimum along the sequence
for i = 1:numParams
    for j = 2: half_autoCorr_length
        Gammas(j, i) = min(Gammas(j, i), Gammas(j - 1, i));        
    end
end


monotoneEstimators = zeros(1, numParams);
for i = 1:numParams
    % Get indices of all Gammas greater than 0
    % Gammas decrease monotonically, so length of positive Gammas
    % is the index where it crosses zero and remains negative
    numPosGammas = length(find(Gammas(:, i) > 0));
    % Sum over all positive Gammas, auto_corrs(1,i) is 1 
    monotoneEstimators(i) = - auto_corrs(1, i) + ...
                              2*sum(Gammas(1: numPosGammas, i));
    
    % monotoneEstimators cannot be less than 1 - fix for when lag 2 corrs < 0
    if monotoneEstimators(i) < 1
        monotoneEstimators(i) = 1;
    end
end

totalESS = numSamples ./ monotoneEstimators;

minESS  = min(totalESS);
meanESS = mean(totalESS);
maxESS  = max(totalESS);

if isTimeNormalized
    totalESS = totalESS / posteriorTime;
    minESS   = minESS   / posteriorTime;
    meanESS  = meanESS  / posteriorTime;
    maxESS   = maxESS   / posteriorTime;
end % if 

end % function


